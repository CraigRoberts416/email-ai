import EmailCard from '@/components/EmailCard';
import EmailCardSkeleton from '@/components/EmailCardSkeleton';
import InboxRecapHeader from '@/components/InboxRecapHeader';
import UnsubscribeToast, { UnsubscribeJob } from '@/components/UnsubscribeToast';
import { GOOGLE_IOS_CLIENT_ID } from '@/constants/auth';
import { Colors, Radius, Spacing, Typography } from '@/constants/theme';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Google from 'expo-auth-session/providers/google';
import { useRouter } from 'expo-router';
import * as SecureStore from 'expo-secure-store';
import { useCallback, useEffect, useRef, useState } from 'react';
import { FlatList, Linking, Pressable, SafeAreaView, StyleSheet, Text, View } from 'react-native';
import { DdRum, RumActionType } from '@datadog/mobile-react-native';

// ─── Feed ─────────────────────────────────────────────────────────────────

const FEED_BASE_URL = process.env.EXPO_PUBLIC_FEED_BASE_URL || 'https://email-ai-server.onrender.com';
const UNSUBSCRIBE_BASE_URL = process.env.EXPO_PUBLIC_UNSUBSCRIBE_BASE_URL || FEED_BASE_URL;

// ─── UI copy ─────────────────────────────────────────────────────────────

type UiCopy = {
  connectGmail: string;
  mailFeed: string;
  allMail: string;
  loadingMore: string;
  loadMore: string;
  unsubscribeStart: string;
  inView: string;
  needAttention: string;
};

const DEFAULT_UI_COPY: UiCopy = {
  connectGmail: 'Connect Gmail',
  mailFeed: 'Mail Feed',
  allMail: 'All Mail',
  loadingMore: 'Loading…',
  loadMore: 'Load More',
  unsubscribeStart: 'Initiating unsubscribe heist…',
  inView: 'in view',
  needAttention: 'need attention',
};

async function fetchUiCopy(token: string): Promise<UiCopy | null> {
  try {
    const res = await fetch(`${FEED_BASE_URL}/ui-copy`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return null;
    return res.json();
  } catch {
    return null;
  }
}

type MessageRecord = {
  messageId:         string;
  threadId:          string | null;
  labelIds:          string[];
  subject:           string;
  fromName:          string;
  fromEmail:         string;
  snippet:           string;
  internalDate:      number;
  postCutoff:        boolean;
  aiStatus:          'none' | 'queued' | 'processing' | 'done' | 'error';
  quote:             string | null;
  summary:           string | null;
  action:            string | null;
  actionUrl:         string | null;
  requiresAttention: boolean;
  unsubscribeUrl:    string | null;
  // Computed server-side
  avatarUri:         string | null;
  avatarFallbackText: string;
  // Only on All Mail cards from server
  interpreted?:      boolean;
};

const FETCH_TIMEOUT_MS = 15_000;

function fetchWithTimeout(url: string, options: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  return fetch(url, { ...options, signal: controller.signal }).finally(() =>
    clearTimeout(timer)
  );
}

async function fetchFeed(accessToken: string): Promise<{ cards: MessageRecord[] }> {
  const res = await fetchWithTimeout(`${FEED_BASE_URL}/feed`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error(`/feed returned ${res.status}`);
  return res.json();
}

async function fetchAllMail(
  accessToken: string,
  cursor?: number
): Promise<{ cards: MessageRecord[]; nextCursor: number | null }> {
  const url = cursor
    ? `${FEED_BASE_URL}/all-mail?cursor=${cursor}`
    : `${FEED_BASE_URL}/all-mail`;
  const res = await fetchWithTimeout(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error(`/all-mail returned ${res.status}`);
  return res.json();
}

async function requestUnsubscribe(
  accessToken: string,
  messageId: string,
  unsubscribeUrl: string,
  senderName: string
): Promise<{ ok: boolean; error?: string; refreshedToken?: string }> {
  const doRequest = (token: string) =>
    fetch(`${UNSUBSCRIBE_BASE_URL}/unsubscribe`, {
      method:  'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body:    JSON.stringify({ messageId, unsubscribeUrl, senderName }),
    });

  try {
    let res = await doRequest(accessToken);

    // If 401, the token has expired — try refreshing once and retry.
    if (res.status === 401) {
      const stored = await loadAuth();
      if (stored?.refreshToken) {
        const refreshed = await refreshAccessToken(stored.refreshToken);
        if (refreshed) {
          await saveAuth(refreshed.accessToken, stored.refreshToken, refreshed.expiresAt);
          res = await doRequest(refreshed.accessToken);
          if (res.ok) return { ok: true, refreshedToken: refreshed.accessToken };
        }
      }
    }

    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      return { ok: false, error: body.error ?? `server error ${res.status}` };
    }
    return { ok: true };
  } catch (err: any) {
    return { ok: false, error: err.message ?? 'network error' };
  }
}

async function fetchUnsubscribeStatus(
  accessToken: string,
  messageId: string
): Promise<UnsubscribeJob | null> {
  try {
    const res = await fetch(`${UNSUBSCRIBE_BASE_URL}/unsubscribe/${encodeURIComponent(messageId)}/status`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`status returned ${res.status}`);
    return res.json();
  } catch (err) {
    console.warn('[unsubscribe] status poll failed:', err);
    return null;
  }
}

async function markAsRead(accessToken: string, messageId: string): Promise<void> {
  await fetch(`${FEED_BASE_URL}/messages/${messageId}/read`, {
    method:  'PATCH',
    headers: { Authorization: `Bearer ${accessToken}` },
  });
}

async function registerWithBackend(
  accessToken: string,
  refreshToken: string,
  expiresAt: number
): Promise<void> {
  try {
    const res = await fetch(`${FEED_BASE_URL}/auth/register`, {
      method:  'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body:    JSON.stringify({ refreshToken, expiresAt }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      console.error('[register] backend registration failed:', JSON.stringify(err));
    } else {
      console.log('[register] backend registration success');
    }
  } catch (err) {
    console.error('[register] backend registration error:', err);
  }
}

// ─── Auth storage ─────────────────────────────────────────────────────────

const AUTH_STORAGE_KEY = 'gmail_auth';
const USER_NAME_KEY = 'user_name';

type RecapData = {
  greeting: string;
  summary: string;
  totalInView: number;
  requireAttention: number;
};

async function saveUserName(name: string) {
  await AsyncStorage.setItem(USER_NAME_KEY, name);
}
async function loadUserName(): Promise<string> {
  return (await AsyncStorage.getItem(USER_NAME_KEY)) ?? '';
}

async function saveAuth(accessToken: string, refreshToken: string | null, expiresAt: number) {
  await SecureStore.setItemAsync(AUTH_STORAGE_KEY, JSON.stringify({ accessToken, refreshToken: refreshToken ?? null, expiresAt }));
}

async function loadAuth(): Promise<{ accessToken: string; refreshToken: string | null; expiresAt: number } | null> {
  const raw = await SecureStore.getItemAsync(AUTH_STORAGE_KEY);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

async function refreshAccessToken(refreshToken: string): Promise<{ accessToken: string; expiresAt: number } | null> {
  const body = new URLSearchParams({
    client_id: GOOGLE_IOS_CLIENT_ID,
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
  }).toString();
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const json = await res.json();
  if (!res.ok) {
    console.error('[auth] refresh failed:', json);
    return null;
  }
  return { accessToken: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
}

// ─── Relative time formatter ──────────────────────────────────────────────

function formatRelativeTime(dateStr: string): string {
  if (!dateStr) return '';
  // Gmail internalDate is epoch ms as a string; fall back to RFC 2822 string
  const asMs = Number(dateStr);
  const date = isNaN(asMs) ? new Date(dateStr) : new Date(asMs);
  if (isNaN(date.getTime())) return '';
  const diffMs = Date.now() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `${diffHours} hour${diffHours === 1 ? '' : 's'} ago`;
  const diffDays = Math.floor(diffHours / 24);
  if (diffDays === 1) return 'Yesterday';
  if (diffDays < 7) return `${diffDays} days ago`;
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

// ─── Screen ───────────────────────────────────────────────────────────────

export default function Index() {
  const router = useRouter();
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [userName, setUserName] = useState('');
  const [recap] = useState<RecapData | null>(null);
  const [uiCopy, setUiCopy] = useState<UiCopy>(DEFAULT_UI_COPY);
  const activeUnsubscribePolls = useRef(new Set<string>());
  const refreshTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Tracks messageIds that have been successfully unsubscribed so the
  // tag on the card can flip from "Unsubscribe" → "Unsubscribed".
  const [unsubscribedIds, setUnsubscribedIds] = useState<Set<string>>(new Set());

  // ── Feed state ────────────────────────────────────────────────────────
  const [feedMessages, setFeedMessages] = useState<MessageRecord[]>([]);

  // ── Unsubscribe toast state ────────────────────────────────────────────
  const [unsubscribeJobs, setUnsubscribeJobs] = useState<UnsubscribeJob[]>([]);

  const pollUnsubscribeStatus = useCallback(async (token: string, messageId: string) => {
    if (activeUnsubscribePolls.current.has(messageId)) return;
    activeUnsubscribePolls.current.add(messageId);

    try {
      const deadline = Date.now() + 180_000;

      while (Date.now() < deadline) {
        const status = await fetchUnsubscribeStatus(token, messageId);
        if (status) {
          console.log('[unsubscribe] polled status:', JSON.stringify(status));
          setUnsubscribeJobs(prev => {
            const exists = prev.find(j => j.messageId === messageId);
            if (exists) return prev.map(j => j.messageId === messageId ? status : j);
            return [...prev, status];
          });

          if (status.status === 'done' || status.status === 'error') return;
        }

        await new Promise(resolve => setTimeout(resolve, 1500));
      }

      setUnsubscribeJobs(prev => prev.map(j =>
        j.messageId === messageId && (j.status === 'queued' || j.status === 'navigating' || j.status === 'analyzing' || j.status === 'filling' || j.status === 'clicking' || j.status === 'verifying')
          ? { ...j, status: 'error', message: 'Timed out waiting for unsubscribe progress' }
          : j
      ));
    } finally {
      activeUnsubscribePolls.current.delete(messageId);
    }
  }, []);

  // Clear successful jobs quickly, but leave errors around longer so we can read them.
  // Also permanently record done IDs so the card tag flips to "Unsubscribed".
  useEffect(() => {
    const doneJobs = unsubscribeJobs.filter(j => j.status === 'done');
    if (doneJobs.length === 0) return;

    // Persist the unsubscribed state on the card immediately (survives toast cleanup)
    setUnsubscribedIds(prev => {
      const next = new Set(prev);
      doneJobs.forEach(j => next.add(j.messageId));
      return next;
    });

    const timer = setTimeout(() => {
      setUnsubscribeJobs(prev => prev.filter(j => j.status !== 'done'));
    }, 5000);
    return () => clearTimeout(timer);
  }, [unsubscribeJobs]);

  useEffect(() => {
    const errorJobs = unsubscribeJobs.filter(j => j.status === 'error');
    if (errorJobs.length === 0) return;
    const timer = setTimeout(() => {
      setUnsubscribeJobs(prev => prev.filter(j => j.status !== 'error'));
    }, 12000);
    return () => clearTimeout(timer);
  }, [unsubscribeJobs]);

  useEffect(() => {
    return () => {
      activeUnsubscribePolls.current.clear();
    };
  }, []);

  // ── All Mail state ────────────────────────────────────────────────────
  const [activeTab, setActiveTab] = useState<'feed' | 'allMail'>('feed');
  const [allMailMessages, setAllMailMessages] = useState<MessageRecord[]>([]);
  const [allMailCursor, setAllMailCursor] = useState<number | null>(null);
  const [loadingAllMail, setLoadingAllMail] = useState(false);

  // Reset All Mail cache when auth changes so a new user gets a fresh fetch
  useEffect(() => {
    setAllMailMessages([]);
    setAllMailCursor(null);
  }, [accessToken]);

  // Fetch AI-generated UI copy once per session when auth is available
  useEffect(() => {
    if (!accessToken) return;
    fetchUiCopy(accessToken).then(copy => { if (copy) setUiCopy(copy); });
  }, [accessToken]);

  // Load feed on mount / when access token becomes available
  const loadFeed = useCallback(async () => {
    if (!accessToken) return;
    try {
      const { cards } = await fetchFeed(accessToken);
      setFeedMessages(cards);
    } catch (err) {
      console.warn('[feed] load failed:', err);
    }
  }, [accessToken]);

  useEffect(() => {
    loadFeed();
  }, [loadFeed]);

  // SSE connection — receives real-time message events while the user is in the app.
  // Handles: message-added, processing, chunk, field-complete, message-ready, message-read
  useEffect(() => {
    if (!accessToken) return;

    const controller = new AbortController();
    const wait = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

    (async () => {
      let retryDelay = 1000;

      while (!controller.signal.aborted) {
        let connectTimer: ReturnType<typeof setTimeout> | null = null;
        const attemptController = new AbortController();
        const abortAttempt = () => attemptController.abort();
        controller.signal.addEventListener('abort', abortAttempt);

        try {
          connectTimer = setTimeout(() => attemptController.abort(), FETCH_TIMEOUT_MS);
          const response = await fetch(`${FEED_BASE_URL}/feed/events`, {
            headers: { Authorization: `Bearer ${accessToken}` },
            signal: attemptController.signal,
          });
          clearTimeout(connectTimer);
          connectTimer = null;

          if (response.status === 401) {
            console.log('[sse] 401 — attempting token refresh');
            const stored = await loadAuth();
            if (stored?.refreshToken) {
              const refreshed = await refreshAccessToken(stored.refreshToken);
              if (refreshed) {
                await saveAuth(refreshed.accessToken, stored.refreshToken, refreshed.expiresAt);
                setAccessToken(refreshed.accessToken);
                break; // exit loop; effect will restart with new token
              }
            }
            console.warn('[sse] 401 and no refresh token available, stopping');
            break;
          }
          if (!response.ok) throw new Error(`connect failed: ${response.status}`);

          const reader = response.body?.getReader();
          if (!reader) throw new Error('SSE response body unavailable');

          retryDelay = 1000;

          const decoder = new TextDecoder();
          let buffer = '';

          while (!controller.signal.aborted) {
            const { done, value } = await reader.read();
            if (done) break;
            buffer += decoder.decode(value, { stream: true });

            const lines = buffer.split('\n');
            buffer = lines.pop() ?? '';

            for (const line of lines) {
              if (!line.startsWith('data: ')) continue;
              try {
                const event = JSON.parse(line.slice(6));
                const { messageId, type: evtType } = event;

                if (evtType === 'message-added') {
                  // New message arrived — add to feed
                  const newRecord: MessageRecord = {
                    messageId:          event.messageId,
                    threadId:           event.threadId ?? null,
                    labelIds:           event.labelIds ?? [],
                    subject:            event.subject ?? '',
                    fromName:           event.fromName ?? '',
                    fromEmail:          event.fromEmail ?? '',
                    snippet:            event.snippet ?? '',
                    internalDate:       event.internalDate ?? Date.now(),
                    postCutoff:         event.postCutoff ?? false,
                    aiStatus:           event.aiStatus ?? 'none',
                    quote:              null,
                    summary:            null,
                    action:             null,
                    actionUrl:          null,
                    requiresAttention:  false,
                    unsubscribeUrl:     null,
                    avatarUri:          event.avatarUri ?? null,
                    avatarFallbackText: event.avatarFallbackText ?? '',
                  };
                  setFeedMessages(prev => {
                    const exists = prev.some(m => m.messageId === newRecord.messageId);
                    if (exists) return prev;
                    return [newRecord, ...prev].sort((a, b) => b.internalDate - a.internalDate);
                  });
                } else if (evtType === 'processing') {
                  // Mark message as processing
                  setFeedMessages(prev => prev.map(m =>
                    m.messageId === messageId ? { ...m, aiStatus: 'processing' } : m
                  ));
                } else if (evtType === 'field-complete') {
                  // Field fully resolved — set final value
                  setFeedMessages(prev => prev.map(m =>
                    m.messageId === messageId ? { ...m, [event.field]: event.value } : m
                  ));
                } else if (evtType === 'message-ready') {
                  // All AI fields done
                  setFeedMessages(prev => prev.map(m =>
                    m.messageId === messageId ? { ...m, aiStatus: 'done' } : m
                  ));
                } else if (evtType === 'message-read') {
                  // Message marked as read — remove from unread feed
                  setFeedMessages(prev => prev.filter(m => m.messageId !== messageId));
                } else if (evtType === 'unsubscribe-status') {
                  setUnsubscribeJobs(prev => {
                    const exists = prev.find(j => j.messageId === messageId);
                    const job: UnsubscribeJob = {
                      messageId,
                      senderName: event.senderName ?? '',
                      status:     event.status,
                      message:    event.message ?? '',
                    };
                    if (exists) return prev.map(j => j.messageId === messageId ? job : j);
                    return [...prev, job];
                  });
                }
              } catch {
                // Skip malformed events.
              }
            }
          }

          // SSE disconnected — reload feed to catch any missed events, then reconnect.
          if (!controller.signal.aborted) {
            await loadFeed();
            await wait(1000);
          }
        } catch (err: any) {
          if (err.name !== 'AbortError') console.warn('[sse] error:', err.message);
          if (controller.signal.aborted) break;
          await wait(retryDelay);
          retryDelay = Math.min(retryDelay * 2, 10_000);
        } finally {
          if (connectTimer) clearTimeout(connectTimer);
          controller.signal.removeEventListener('abort', abortAttempt);
        }
      }
    })();

    return () => controller.abort();
  }, [accessToken, loadFeed]);

  useEffect(() => {
    if (!accessToken) return;
    if (UNSUBSCRIBE_BASE_URL === FEED_BASE_URL) return;

    const controller = new AbortController();
    const wait = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

    (async () => {
      let retryDelay = 1000;

      while (!controller.signal.aborted) {
        let connectTimer: ReturnType<typeof setTimeout> | null = null;
        const attemptController = new AbortController();
        const abortAttempt = () => attemptController.abort();
        controller.signal.addEventListener('abort', abortAttempt);

        try {
          connectTimer = setTimeout(() => attemptController.abort(), FETCH_TIMEOUT_MS);
          const response = await fetch(`${UNSUBSCRIBE_BASE_URL}/feed/events`, {
            headers: { Authorization: `Bearer ${accessToken}` },
            signal: attemptController.signal,
          });
          clearTimeout(connectTimer);
          connectTimer = null;

          if (!response.ok) throw new Error(`unsubscribe SSE failed: ${response.status}`);

          const reader = response.body?.getReader();
          if (!reader) throw new Error('unsubscribe SSE response body unavailable');

          retryDelay = 1000;

          const decoder = new TextDecoder();
          let buffer = '';

          while (!controller.signal.aborted) {
            const { done, value } = await reader.read();
            if (done) break;
            buffer += decoder.decode(value, { stream: true });

            const lines = buffer.split('\n');
            buffer = lines.pop() ?? '';

            for (const line of lines) {
              if (!line.startsWith('data: ')) continue;
              try {
                const event = JSON.parse(line.slice(6));
                if (event.type !== 'unsubscribe-status') continue;

                setUnsubscribeJobs(prev => {
                  const exists = prev.find(j => j.messageId === event.messageId);
                  const job: UnsubscribeJob = {
                    messageId: event.messageId,
                    senderName: event.senderName ?? '',
                    status: event.status,
                    message: event.message ?? '',
                  };
                  if (exists) return prev.map(j => j.messageId === event.messageId ? job : j);
                  return [...prev, job];
                });
              } catch {
                // Skip malformed events.
              }
            }
          }

          if (!controller.signal.aborted) await wait(1000);
        } catch (err: any) {
          if (err.name !== 'AbortError') console.warn('[unsubscribe-sse] error:', err.message);
          if (controller.signal.aborted) break;
          await wait(retryDelay);
          retryDelay = Math.min(retryDelay * 2, 10_000);
        } finally {
          if (connectTimer) clearTimeout(connectTimer);
          controller.signal.removeEventListener('abort', abortAttempt);
        }
      }
    })();

    return () => controller.abort();
  }, [accessToken]);

  const handleTabChange = useCallback(async (tab: 'feed' | 'allMail') => {
    const screen = tab === 'feed' ? 'inbox' : 'all_mail';
    DdRum.addAction(RumActionType.TAP, 'tab_tapped', { feed_mode: tab, current_screen: screen });
    DdRum.addViewAttribute('feed_mode', tab);
    DdRum.addViewAttribute('current_screen', screen);
    setActiveTab(tab);
    if (tab === 'allMail' && accessToken) {
      DdRum.addViewAttribute('sync_in_progress', true);
      setLoadingAllMail(true);
      try {
        const { cards, nextCursor } = await fetchAllMail(accessToken);
        setAllMailMessages(cards);
        setAllMailCursor(nextCursor);
        DdRum.addAction(RumActionType.CUSTOM, 'all_mail_loaded', { card_count: cards.length, feed_mode: 'all_mail' });
        DdRum.addViewAttribute('card_count', cards.length);
      } catch (err) {
        console.error('[all-mail] fetch failed:', err);
      } finally {
        setLoadingAllMail(false);
        DdRum.addViewAttribute('sync_in_progress', false);
      }
    }
  }, [accessToken]);

  const handleLoadMoreAllMail = useCallback(async () => {
    if (!accessToken || !allMailCursor || loadingAllMail) return;
    setLoadingAllMail(true);
    try {
      const { cards, nextCursor } = await fetchAllMail(accessToken, allMailCursor);
      setAllMailMessages(prev => [...prev, ...cards]);
      setAllMailCursor(nextCursor);
    } catch (err) {
      console.error('[all-mail] load more failed:', err);
    } finally {
      setLoadingAllMail(false);
    }
  }, [accessToken, allMailCursor, loadingAllMail]);

  // Re-render every minute so relative timestamps stay current
  const [, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick(t => t + 1), 60_000);
    return () => clearInterval(id);
  }, []);

  // Restore auth on launch
  useEffect(() => {
    (async () => {
      try {
        const stored = await loadAuth();
        if (!stored) { console.log('[auth] no stored session'); return; }
        const isExpired = Date.now() >= stored.expiresAt - 60_000;
        if (isExpired) {
          console.log('[auth] stored token expired, refreshing...');
          if (!stored.refreshToken) {
            console.log('[auth] token expired and no refresh token, clearing session');
            await SecureStore.deleteItemAsync(AUTH_STORAGE_KEY);
          } else {
            const refreshed = await refreshAccessToken(stored.refreshToken);
            if (refreshed) {
              await saveAuth(refreshed.accessToken, stored.refreshToken, refreshed.expiresAt);
              console.log('[auth] session restored via refresh');
              // Register first so incremental sync runs before loadFeed fires
              await registerWithBackend(refreshed.accessToken, stored.refreshToken, refreshed.expiresAt);
              setAccessToken(refreshed.accessToken);
            } else {
              await SecureStore.deleteItemAsync(AUTH_STORAGE_KEY);
              console.log('[auth] refresh failed, cleared stored session');
            }
          }
        } else {
          console.log('[auth] session restored from storage');
          // Register first so incremental sync runs before loadFeed fires
          if (stored.refreshToken) {
            await registerWithBackend(stored.accessToken, stored.refreshToken, stored.expiresAt);
          }
          setAccessToken(stored.accessToken);
        }
      } catch (err) {
        console.error('[auth] restore error:', err);
      }
    })();
  }, []);

  // Proactively refresh the access token 5 minutes before it expires.
  // Google tokens last ~1 hour. Without this, the SSE and API calls start
  // failing with 401 after the first hour the app is open.
  useEffect(() => {
    if (!accessToken) return;

    const doRefresh = async () => {
      const s = await loadAuth();
      if (!s?.refreshToken) return;
      console.log('[auth] proactive token refresh');
      const r = await refreshAccessToken(s.refreshToken);
      if (r) {
        await saveAuth(r.accessToken, s.refreshToken, r.expiresAt);
        setAccessToken(r.accessToken);
      }
    };

    (async () => {
      const stored = await loadAuth();
      if (!stored?.refreshToken || !stored.expiresAt) return;
      const msUntilRefresh = stored.expiresAt - Date.now() - 5 * 60 * 1000;
      if (msUntilRefresh <= 0) {
        await doRefresh();
      } else {
        if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current);
        refreshTimerRef.current = setTimeout(doRefresh, msUntilRefresh);
      }
    })();

    return () => {
      if (refreshTimerRef.current) {
        clearTimeout(refreshTimerRef.current);
        refreshTimerRef.current = null;
      }
    };
  }, [accessToken]);

  // Restore user name on launch
  useEffect(() => {
    loadUserName().then(n => { if (n) setUserName(n); });
  }, []);

  // Set initial RUM attributes when the screen mounts.
  useEffect(() => {
    DdRum.addViewAttribute('current_screen', 'inbox');
    DdRum.addViewAttribute('feed_mode', 'feed');
    DdRum.addViewAttribute('overlay_visible', false);
    DdRum.addViewAttribute('card_count', 0);
    DdRum.addViewAttribute('sync_in_progress', false);
  }, []);

  // Keep sync_in_progress and card_count current as feed state changes.
  useEffect(() => {
    DdRum.addViewAttribute('sync_in_progress', feedMessages.some(m => m.aiStatus === 'processing'));
    DdRum.addViewAttribute('card_count', feedMessages.length);
  }, [feedMessages]);

  const [request, response, promptAsync] = Google.useAuthRequest({
    iosClientId: GOOGLE_IOS_CLIENT_ID,
    scopes: ['openid', 'profile', 'email', 'https://mail.google.com/'],
    shouldAutoExchangeCode: false,
  });

  useEffect(() => {
    if (response?.type !== 'success') return;

    const code = response.params.code;
    const codeVerifier = request?.codeVerifier;
    const redirectUri = request?.redirectUri;

    console.log('[auth] code received:', code);
    console.log('[auth] code_verifier (PKCE):', codeVerifier);
    console.log('[auth] redirect_uri used:', redirectUri);
    console.log('[auth] client_id:', GOOGLE_IOS_CLIENT_ID);

    if (!code || !codeVerifier || !redirectUri) {
      console.error('[auth] missing values:', { code: !!code, codeVerifier: !!codeVerifier, redirectUri: !!redirectUri });
      return;
    }

    const exchangeToken = async () => {
      const body = new URLSearchParams({
        client_id: GOOGLE_IOS_CLIENT_ID,
        grant_type: 'authorization_code',
        code,
        redirect_uri: redirectUri,
        code_verifier: codeVerifier,
      }).toString();

      try {
        const res = await fetch('https://oauth2.googleapis.com/token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body,
        });
        const json = await res.json();
        console.log('[auth] token response:', JSON.stringify(json, null, 2));
        if (!res.ok) {
          console.error('[auth] token error:', JSON.stringify(json, null, 2));
          return;
        }

        const newAccessToken = json.access_token;
        const existingAuth = await loadAuth();
        const refreshToken = json.refresh_token ?? existingAuth?.refreshToken ?? null;
        const expiresAt = Date.now() + json.expires_in * 1000;
        await saveAuth(newAccessToken, refreshToken, expiresAt);
        console.log('[auth] refresh_token present:', !!refreshToken);
        console.log('[auth] tokens saved to secure storage');

        // Register with backend — starts initial sync, worker, and watch
        if (refreshToken) {
          await registerWithBackend(newAccessToken, refreshToken, expiresAt);
        }
        setAccessToken(newAccessToken);

        console.log('[gmail] fetching profile with access_token:', newAccessToken);

        const profileRes = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/profile', {
          headers: { Authorization: `Bearer ${newAccessToken}` },
        });
        const profileJson = await profileRes.json();
        console.log('[gmail] profile:', JSON.stringify(profileJson, null, 2));

        const userInfoRes = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
          headers: { Authorization: `Bearer ${newAccessToken}` },
        });
        const userInfoJson = await userInfoRes.json();
        const firstName = userInfoJson.given_name ?? '';
        if (firstName) { setUserName(firstName); await saveUserName(firstName); }
      } catch (err) {
        console.error('[auth] token exchange failed:', err);
      }
    };

    exchangeToken();
  }, [response]);

  const listHeader = (
    <>
      {recap && <InboxRecapHeader recap={recap} inViewLabel={uiCopy.inView} needAttentionLabel={uiCopy.needAttention} />}
      <Pressable
        style={({ pressed }) => [styles.connectBtn, pressed && styles.connectBtnPressed]}
        onPress={() => promptAsync()}
        disabled={!request}
      >
        <Text style={styles.connectLabel}>{uiCopy.connectGmail}</Text>
      </Pressable>
      {/* DEV ONLY — auth state diagnostic, remove before launch */}
      <Text style={styles.devStatus}>
        {accessToken ? `token: live (${accessToken.slice(0, 8)}…)` : 'token: none — tap Connect Gmail to re-authorise'}
      </Text>
      {/* ── Surface toggle ──────────────────────────────────────── */}
      <View style={styles.toggle}>
        <Pressable
          style={[styles.toggleBtn, activeTab === 'feed' && styles.toggleBtnActive]}
          onPress={() => handleTabChange('feed')}
        >
          <Text style={[styles.toggleLabel, activeTab === 'feed' && styles.toggleLabelActive]}>
            {uiCopy.mailFeed}
          </Text>
        </Pressable>
        <Pressable
          style={[styles.toggleBtn, activeTab === 'allMail' && styles.toggleBtnActive]}
          onPress={() => handleTabChange('allMail')}
        >
          <Text style={[styles.toggleLabel, activeTab === 'allMail' && styles.toggleLabelActive]}>
            {uiCopy.allMail}
          </Text>
        </Pressable>
      </View>
      {activeTab === 'allMail' && loadingAllMail && allMailMessages.length === 0 && (
        <EmailCardSkeleton />
      )}
    </>
  );

  const activeMessages = activeTab === 'feed' ? feedMessages : allMailMessages;

  return (
    <SafeAreaView style={styles.safe}>
      <UnsubscribeToast jobs={unsubscribeJobs} />
      <FlatList
        data={activeMessages}
        keyExtractor={m => m.messageId}
        contentContainerStyle={styles.content}
        ListHeaderComponent={listHeader}
        ItemSeparatorComponent={() => <View style={{ height: Spacing.sm }} />}
        onEndReached={activeTab === 'allMail' ? handleLoadMoreAllMail : undefined}
        onEndReachedThreshold={0.3}
        ListFooterComponent={
          activeTab === 'allMail' && allMailCursor ? (
            <Pressable
              style={({ pressed }) => [styles.connectBtn, pressed && styles.connectBtnPressed, { marginTop: Spacing.sm }]}
              onPress={handleLoadMoreAllMail}
              disabled={loadingAllMail}
            >
              <Text style={styles.connectLabel}>{loadingAllMail ? uiCopy.loadingMore : uiCopy.loadMore}</Text>
            </Pressable>
          ) : null
        }
        renderItem={({ item: m }) => {
          if (activeTab === 'feed') {
            return (
              <Pressable
                onPress={() => {
                  DdRum.addAction(RumActionType.TAP, 'card_tapped', {
                    feed_mode: 'feed',
                    current_screen: 'inbox',
                    ai_status: m.aiStatus,
                  });
                  router.push(`/email/${m.messageId}` as any);
                }}
              >
                {!m.fromName ? (
                  <EmailCardSkeleton />
                ) : (
                  <EmailCard
                    sender={{
                      name: m.fromName,
                      email: m.fromEmail,
                      avatarUri: m.avatarUri ?? undefined,
                      avatarFallbackText: m.avatarFallbackText,
                    }}
                    content={{
                      contentType: 'structured',
                      headline: m.quote,
                      subtitle: m.subject,
                      body: m.summary,
                      bodySummary: true,
                      cta: m.action && m.actionUrl
                        ? { label: m.action, onPress: () => Linking.openURL(m.actionUrl!) }
                        : undefined,
                      actionLabel: m.action && !m.actionUrl ? m.action : undefined,
                    }}
                    tag={unsubscribedIds.has(m.messageId) ? 'Unsubscribed' : m.unsubscribeUrl ? 'Unsubscribe' : undefined}
                    loading={m.aiStatus !== 'done'}
                    timestamp={formatRelativeTime(String(m.internalDate))}
                    actions={{
                      aiSuggestionCount: 0,
                      onReply: () => DdRum.addAction(RumActionType.TAP, 'reply_tapped', {
                        feed_mode: 'feed',
                        current_screen: 'inbox',
                      }),
                      onAI: () => DdRum.addAction(RumActionType.TAP, 'discuss_tapped', {
                        feed_mode: 'feed',
                        current_screen: 'inbox',
                      }),
                      onDelete: accessToken
                        ? () => markAsRead(accessToken, m.messageId).catch(err =>
                            console.error('[read] markAsRead failed:', err)
                          )
                        : undefined,
                      onUnsubscribe: accessToken && m.unsubscribeUrl && !unsubscribedIds.has(m.messageId)
                        ? () => {
                            setUnsubscribeJobs(prev => {
                              if (prev.find(j => j.messageId === m.messageId)) return prev;
                              return [...prev, { messageId: m.messageId, senderName: m.fromName || m.fromEmail, status: 'queued', message: uiCopy.unsubscribeStart }];
                            });
                            requestUnsubscribe(
                              accessToken,
                              m.messageId,
                              m.unsubscribeUrl!,
                              m.fromName || m.fromEmail
                            ).then(result => {
                              if (!result.ok) {
                                setUnsubscribeJobs(prev => prev.map(j =>
                                  j.messageId === m.messageId
                                    ? { ...j, status: 'error', message: result.error ?? 'Failed' }
                                    : j
                                ));
                              } else {
                                if (result.refreshedToken) setAccessToken(result.refreshedToken);
                                const pollToken = result.refreshedToken ?? accessToken;
                                pollUnsubscribeStatus(pollToken, m.messageId).catch(err =>
                                  console.warn('[unsubscribe] poll failed:', err)
                                );
                              }
                            });
                          }
                        : undefined,
                    }}
                  />
                )}
              </Pressable>
            );
          }

          // All Mail
          const headline = m.quote   || m.subject || null;
          const body     = m.summary || (m.snippet ? m.snippet + ' See more...' : null);
          return (
            <Pressable
              onPress={() => {
                DdRum.addAction(RumActionType.TAP, 'card_tapped', {
                  feed_mode: 'all_mail',
                  current_screen: 'all_mail',
                  interpreted: m.interpreted ?? false,
                });
                router.push(`/email/${m.messageId}` as any);
              }}
            >
              <EmailCard
                sender={{
                  name: m.fromName,
                  email: m.fromEmail,
                  avatarUri: m.avatarUri ?? undefined,
                  avatarFallbackText: m.avatarFallbackText,
                }}
                content={{
                  contentType: 'structured',
                  headline,
                  subtitle: m.interpreted ? m.subject : null,
                  body,
                  bodySummary: !!m.interpreted,
                  cta: m.action && m.actionUrl
                    ? { label: m.action, onPress: () => Linking.openURL(m.actionUrl!) }
                    : undefined,
                  actionLabel: m.action && !m.actionUrl ? m.action : undefined,
                }}
                tag={unsubscribedIds.has(m.messageId) ? 'Unsubscribed' : m.unsubscribeUrl ? 'Unsubscribe' : undefined}
                loading={false}
                timestamp={formatRelativeTime(String(m.internalDate))}
                actions={{
                  aiSuggestionCount: 0,
                  onReply: () => DdRum.addAction(RumActionType.TAP, 'reply_tapped', {
                    feed_mode: 'all_mail',
                    current_screen: 'all_mail',
                  }),
                  onAI: () => DdRum.addAction(RumActionType.TAP, 'discuss_tapped', {
                    feed_mode: 'all_mail',
                    current_screen: 'all_mail',
                  }),
                  onUnsubscribe: accessToken && m.unsubscribeUrl && !unsubscribedIds.has(m.messageId)
                    ? () => {
                        setUnsubscribeJobs(prev => {
                          if (prev.find(j => j.messageId === m.messageId)) return prev;
                          return [...prev, { messageId: m.messageId, senderName: m.fromName || m.fromEmail, status: 'queued', message: uiCopy.unsubscribeStart }];
                        });
                        requestUnsubscribe(
                          accessToken,
                          m.messageId,
                          m.unsubscribeUrl!,
                          m.fromName || m.fromEmail
                        ).then(result => {
                          if (!result.ok) {
                            setUnsubscribeJobs(prev => prev.map(j =>
                              j.messageId === m.messageId
                                ? { ...j, status: 'error', message: result.error ?? 'Failed' }
                                : j
                            ));
                          } else {
                            if (result.refreshedToken) setAccessToken(result.refreshedToken);
                            const pollToken = result.refreshedToken ?? accessToken;
                            pollUnsubscribeStatus(pollToken, m.messageId).catch(err =>
                              console.warn('[unsubscribe] poll failed:', err)
                            );
                          }
                        });
                      }
                    : undefined,
                }}
              />
            </Pressable>
          );
        }}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: Colors.light.background,
  },
  content: {
    padding: Spacing.sm,
  },
  connectBtn: {
    backgroundColor: Colors.light.surface,
    borderRadius: Radius.md,
    paddingHorizontal: Spacing.md,
    paddingVertical: Spacing.sm,
    alignItems: 'center',
    marginBottom: Spacing.lg,
  },
  connectBtnPressed: {
    opacity: 0.6,
  },
  devStatus: {
    ...Typography.bodySm,
    color: Colors.light.textSecondary,
    textAlign: 'center',
    marginBottom: Spacing.lg,
  },
  toggle: {
    flexDirection: 'row',
    backgroundColor: Colors.light.surface,
    borderRadius: Radius.md,
    padding: 2,
    marginBottom: Spacing.lg,
  },
  toggleBtn: {
    flex: 1,
    paddingVertical: Spacing.sm,
    alignItems: 'center',
    borderRadius: Radius.md,
  },
  toggleBtnActive: {
    backgroundColor: Colors.light.background,
    borderWidth: 1,
    borderColor: Colors.light.border,
  },
  toggleLabel: {
    ...Typography.bodySm,
    color: Colors.light.textSecondary,
  },
  toggleLabelActive: {
    color: Colors.light.textPrimary,
  },
  connectLabel: {
    ...Typography.bodySm,
    color: Colors.light.textPrimary,
  },
});
