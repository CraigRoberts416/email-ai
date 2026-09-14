import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Platform,
  Pressable,
  RefreshControl,
  StatusBar,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import Animated, {
  useAnimatedScrollHandler,
  useSharedValue,
} from 'react-native-reanimated';
import { SafeAreaView } from 'react-native-safe-area-context';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Google from 'expo-auth-session/providers/google';
import * as Haptics from 'expo-haptics';
import * as Notifications from 'expo-notifications';
import { useRouter } from 'expo-router';
import * as SecureStore from 'expo-secure-store';
import { trackAction } from '@/components/observability';
import { registerBackgroundFetch } from '@/tasks/backgroundFetch';

import CaughtUp from '@/components/CaughtUp';
import DiscussSheet, { DiscussMessage } from '@/components/DiscussSheet';
import EmptyState from '@/components/EmptyState';
import FeedCard from '@/components/FeedCard';
import FeedHeader, { FeedMode } from '@/components/FeedHeader';
import OverflowMenu, { OverflowItem } from '@/components/OverflowMenu';
import { StatusKind } from '@/components/StatusPill';
import UnsubscribeToast, { UnsubscribeJob } from '@/components/UnsubscribeToast';
import { GOOGLE_IOS_CLIENT_ID } from '@/constants/auth';
import { Spacing, Theme } from '@/constants/theme';

const AnimatedFlatList = Animated.createAnimatedComponent(FlatList);

// Push arrives silently — it exists to wake background fetch so the feed is
// already warm when the user opens the app, not to interrupt them.
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert:  false,
    shouldShowBanner: false,
    shouldShowList:   false,
    shouldPlaySound:  false,
    shouldSetBadge:   false,
  }),
});

// ─── Backend endpoints ───────────────────────────────────────────────────

const FEED_BASE_URL = process.env.EXPO_PUBLIC_FEED_BASE_URL || 'https://email-ai-server.onrender.com';
const UNSUBSCRIBE_BASE_URL = process.env.EXPO_PUBLIC_UNSUBSCRIBE_BASE_URL || FEED_BASE_URL;

// ─── Data types ──────────────────────────────────────────────────────────

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
  avatarUri:         string | null;
  avatarFallbackText: string;
  heroImageUrl:      string | null;
  heroImageBgColor:  string | null;
  // Only on All Mail cards from server
  interpreted?:      boolean;
};

// AI-written greeting + tally for the feed header. Zero-shot: the server
// generates the wording, the client never templates it.
type RecapData = {
  greeting:         string;
  summary:          string;
  totalInView:      number;
  requireAttention: number;
};

// ─── HTTP helpers ────────────────────────────────────────────────────────

const FETCH_TIMEOUT_MS = 15_000;

function fetchWithTimeout(url: string, options: RequestInit): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  return fetch(url, { ...options, signal: controller.signal }).finally(() => clearTimeout(timer));
}

async function fetchFeed(token: string) {
  const res = await fetchWithTimeout(`${FEED_BASE_URL}/feed`, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`feed ${res.status}`);
  return res.json() as Promise<{ cards: MessageRecord[]; recap?: RecapData | null }>;
}

async function registerPushToken(accessToken: string): Promise<void> {
  if (Platform.OS === 'web') return;
  try {
    const { status: existing } = await Notifications.getPermissionsAsync();
    const { status } = existing === 'granted'
      ? { status: existing }
      : await Notifications.requestPermissionsAsync();
    if (status !== 'granted') return;

    const { data: pushToken } = await Notifications.getExpoPushTokenAsync({
      projectId: '5abdcca5-eea7-41f6-bf4e-ab6b45ed62eb',
    });

    await fetch(`${FEED_BASE_URL}/auth/push-token`, {
      method:  'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body:    JSON.stringify({ pushToken }),
    });

    await registerBackgroundFetch();
  } catch (err: any) {
    console.warn('[push] registration failed:', err.message);
  }
}

async function fetchAllMail(token: string, cursor?: number) {
  const url = cursor ? `${FEED_BASE_URL}/all-mail?cursor=${cursor}` : `${FEED_BASE_URL}/all-mail`;
  const res = await fetchWithTimeout(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`all-mail ${res.status}`);
  return res.json() as Promise<{ cards: MessageRecord[]; nextCursor: number | null }>;
}

async function markAsRead(token: string, messageId: string) {
  await fetch(`${FEED_BASE_URL}/messages/${messageId}/read`, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${token}` },
  });
}

async function requestUnsubscribe(
  accessToken: string, messageId: string, unsubscribeUrl: string, senderName: string
): Promise<{ ok: boolean; error?: string; refreshedToken?: string }> {
  const doRequest = (token: string) =>
    fetch(`${UNSUBSCRIBE_BASE_URL}/unsubscribe`, {
      method:  'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body:    JSON.stringify({ messageId, unsubscribeUrl, senderName }),
    });

  try {
    let res = await doRequest(accessToken);

    // A 401 here means the token expired mid-session. Refresh once and retry
    // rather than surfacing an auth error for something the user can't fix.
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

async function fetchUnsubscribeStatus(token: string, messageId: string): Promise<UnsubscribeJob | null> {
  try {
    const res = await fetch(`${UNSUBSCRIBE_BASE_URL}/unsubscribe/${encodeURIComponent(messageId)}/status`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`status ${res.status}`);
    return res.json();
  } catch (err) {
    console.warn('[unsubscribe] status poll failed:', err);
    return null;
  }
}

async function registerWithBackend(accessToken: string, refreshToken: string, expiresAt: number) {
  try {
    await fetch(`${FEED_BASE_URL}/auth/register`, {
      method:  'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body:    JSON.stringify({ refreshToken, expiresAt }),
    });
  } catch (err) {
    console.error('[register] error:', err);
  }
}

// ─── Auth storage ────────────────────────────────────────────────────────

const AUTH_STORAGE_KEY = 'gmail_auth';
const USER_NAME_KEY    = 'user_name';
const FEED_CACHE_KEY   = 'feed_cache';

async function saveAuth(accessToken: string, refreshToken: string | null, expiresAt: number) {
  await SecureStore.setItemAsync(AUTH_STORAGE_KEY, JSON.stringify({ accessToken, refreshToken, expiresAt }));
}

async function loadAuth(): Promise<{ accessToken: string; refreshToken: string | null; expiresAt: number } | null> {
  const raw = await SecureStore.getItemAsync(AUTH_STORAGE_KEY);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

async function refreshAccessToken(refreshToken: string) {
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
  if (!res.ok) return null;
  const json = await res.json();
  return { accessToken: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
}

// ─── Status derivation ───────────────────────────────────────────────────
// The server doesn't yet return an enum status, so we derive one client-side.
// TODO: move to server once the AI pipeline emits `status` directly.

function deriveStatus(m: MessageRecord): StatusKind {
  if (m.unsubscribeUrl)     return 'promotion';
  if (m.requiresAttention)  return 'waiting-on-you';
  return 'fyi';
}

function deriveKind(m: MessageRecord): 'standard' | 'marketing' {
  return m.unsubscribeUrl ? 'marketing' : 'standard';
}

// ─── Relative time ───────────────────────────────────────────────────────

function relativeTime(ms: number): string {
  const diff = Date.now() - ms;
  const m = Math.floor(diff / 60_000);
  if (m < 1)  return 'now';
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  const d = Math.floor(h / 24);
  if (d < 7) return `${d}d`;
  return new Date(ms).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

// ─── Screen ──────────────────────────────────────────────────────────────

export default function Index() {
  const router = useRouter();
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [userName, setUserName]       = useState('');
  const [mode, setMode]               = useState<FeedMode>('feed');
  const [refreshing, setRefreshing]   = useState(false);
  const [recap, setRecap]             = useState<RecapData | null>(null);

  // Feed state
  const [feedMessages, setFeedMessages] = useState<MessageRecord[]>([]);

  // All-mail state
  const [allMail, setAllMail]           = useState<MessageRecord[]>([]);
  const [allMailCursor, setAllMailCursor] = useState<number | null>(null);
  const [loadingAllMail, setLoadingAllMail] = useState(false);

  // Unsubscribe jobs
  const [unsubscribeJobs, setUnsubscribeJobs] = useState<UnsubscribeJob[]>([]);
  const activePolls = useRef(new Set<string>());

  // Overflow menu state
  const [overflowFor, setOverflowFor] = useState<string | null>(null);

  // Discuss sheet state
  const [discussFor, setDiscussFor] = useState<string | null>(null);
  const [discussMessages, setDiscussMessages] = useState<Record<string, DiscussMessage[]>>({});

  // Scroll-driven header
  const scrollY = useSharedValue(0);
  const onScroll = useAnimatedScrollHandler({
    onScroll: (e) => { scrollY.value = e.contentOffset.y; },
  });

  // Cards that arrived via SSE after the initial load. Only these get an
  // entry animation — FlatList remounts recycled rows while scrolling, and
  // animating those makes the whole list twitch.
  const [newIds, setNewIds] = useState<Set<string>>(new Set());
  const markNew = useCallback((id: string) => {
    setNewIds(prev => new Set(prev).add(id));
    setTimeout(() => {
      setNewIds(prev => {
        const next = new Set(prev);
        next.delete(id);
        return next;
      });
    }, 1000);
  }, []);

  // ── Auth restore on launch ──────────────────────────────────────────
  useEffect(() => {
    (async () => {
      const stored = await loadAuth();
      if (!stored) return;
      const expired = Date.now() >= stored.expiresAt - 60_000;
      if (expired) {
        if (!stored.refreshToken) { await SecureStore.deleteItemAsync(AUTH_STORAGE_KEY); return; }
        const r = await refreshAccessToken(stored.refreshToken);
        if (!r) { await SecureStore.deleteItemAsync(AUTH_STORAGE_KEY); return; }
        await saveAuth(r.accessToken, stored.refreshToken, r.expiresAt);
        await registerWithBackend(r.accessToken, stored.refreshToken, r.expiresAt);
        setAccessToken(r.accessToken);
      } else {
        if (stored.refreshToken) await registerWithBackend(stored.accessToken, stored.refreshToken, stored.expiresAt);
        setAccessToken(stored.accessToken);
      }
    })().catch(err => console.error('[auth] restore error:', err));
  }, []);

  useEffect(() => {
    AsyncStorage.getItem(USER_NAME_KEY).then(n => n && setUserName(n));
  }, []);

  // ── Google OAuth ────────────────────────────────────────────────────
  const [request, response, promptAsync] = Google.useAuthRequest({
    iosClientId: GOOGLE_IOS_CLIENT_ID,
    scopes: ['openid', 'profile', 'email', 'https://mail.google.com/'],
    shouldAutoExchangeCode: false,
  });

  useEffect(() => {
    if (response?.type !== 'success') return;
    const code = response.params.code;
    const codeVerifier = request?.codeVerifier;
    const redirectUri  = request?.redirectUri;
    if (!code || !codeVerifier || !redirectUri) return;

    (async () => {
      const body = new URLSearchParams({
        client_id: GOOGLE_IOS_CLIENT_ID,
        grant_type: 'authorization_code',
        code,
        redirect_uri: redirectUri,
        code_verifier: codeVerifier,
      }).toString();
      const res = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body,
      });
      const json = await res.json();
      if (!res.ok) { console.error('[auth] token error:', json); return; }
      const newAccessToken = json.access_token;
      const existing = await loadAuth();
      const refreshToken = json.refresh_token ?? existing?.refreshToken ?? null;
      const expiresAt    = Date.now() + json.expires_in * 1000;
      await saveAuth(newAccessToken, refreshToken, expiresAt);
      if (refreshToken) await registerWithBackend(newAccessToken, refreshToken, expiresAt);
      setAccessToken(newAccessToken);

      const uiRes = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
        headers: { Authorization: `Bearer ${newAccessToken}` },
      });
      const ui = await uiRes.json();
      const firstName = ui.given_name ?? '';
      if (firstName) { setUserName(firstName); AsyncStorage.setItem(USER_NAME_KEY, firstName); }
    })().catch(err => console.error('[auth] exchange failed:', err));
  }, [response, request]);

  // ── Feed load ───────────────────────────────────────────────────────
  const loadFeed = useCallback(async () => {
    if (!accessToken) return;
    try {
      const { cards, recap: incoming } = await fetchFeed(accessToken);
      setFeedMessages(cards);
      if (incoming) setRecap(incoming);
      AsyncStorage.setItem(FEED_CACHE_KEY, JSON.stringify(cards)).catch(() => {});
    } catch (err) {
      console.warn('[feed] load failed:', err);
    }
  }, [accessToken]);

  useEffect(() => { loadFeed(); }, [loadFeed]);

  // Hydrate from the last cached feed before auth resolves, so opening the
  // app lands on content instead of an empty screen. Background fetch keeps
  // this warm between sessions.
  useEffect(() => {
    AsyncStorage.getItem(FEED_CACHE_KEY).then(raw => {
      if (!raw) return;
      try {
        const cached = JSON.parse(raw) as MessageRecord[];
        setFeedMessages(prev => (prev.length > 0 ? prev : cached));
      } catch {}
    });
  }, []);

  // Register for silent push once we have a token.
  useEffect(() => {
    if (!accessToken) return;
    registerPushToken(accessToken);
  }, [accessToken]);

  // ── SSE ─────────────────────────────────────────────────────────────
  // handleEvent only closes over stable setters and markNew, so the SSE
  // effect below can depend on it without churning the connection.
  const handleEvent = useCallback((event: any) => {
    const { messageId, type } = event;
    if (type === 'message-added') {
      const record: MessageRecord = {
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
        heroImageUrl:       event.heroImageUrl ?? null,
        heroImageBgColor:   event.heroImageBgColor ?? null,
      };
      setFeedMessages(prev => {
        if (prev.some(m => m.messageId === record.messageId)) return prev;
        markNew(record.messageId);
        return [record, ...prev].sort((a, b) => b.internalDate - a.internalDate);
      });
    } else if (type === 'processing') {
      setFeedMessages(prev => prev.map(m => m.messageId === messageId ? { ...m, aiStatus: 'processing' } : m));
    } else if (type === 'field-complete') {
      setFeedMessages(prev => prev.map(m => m.messageId === messageId ? { ...m, [event.field]: event.value } : m));
    } else if (type === 'message-ready') {
      setFeedMessages(prev => prev.map(m => m.messageId === messageId ? { ...m, aiStatus: 'done' } : m));
    } else if (type === 'message-read') {
      setFeedMessages(prev => prev.filter(m => m.messageId !== messageId));
    } else if (type === 'unsubscribe-status') {
      setUnsubscribeJobs(prev => {
        const job: UnsubscribeJob = {
          messageId,
          senderName: event.senderName ?? '',
          status:     event.status,
          message:    event.message ?? '',
        };
        const existing = prev.find(j => j.messageId === messageId);
        if (existing) return prev.map(j => j.messageId === messageId ? job : j);
        return [...prev, job];
      });
    }
  }, [markNew]);

  useEffect(() => {
    if (!accessToken) return;
    const controller = new AbortController();
    const wait = (ms: number) => new Promise(r => setTimeout(r, ms));

    (async () => {
      let backoff = 1000;
      while (!controller.signal.aborted) {
        try {
          const response = await fetch(`${FEED_BASE_URL}/feed/events`, {
            headers: { Authorization: `Bearer ${accessToken}` },
            signal: controller.signal,
          });
          if (!response.ok) throw new Error(`connect ${response.status}`);
          const reader = response.body?.getReader();
          if (!reader) throw new Error('no body');
          backoff = 1000;
          const dec = new TextDecoder();
          let buf = '';
          while (!controller.signal.aborted) {
            const { done, value } = await reader.read();
            if (done) break;
            buf += dec.decode(value, { stream: true });
            const lines = buf.split('\n');
            buf = lines.pop() ?? '';
            for (const line of lines) {
              if (!line.startsWith('data: ')) continue;
              try {
                const evt = JSON.parse(line.slice(6));
                handleEvent(evt);
              } catch { /* skip malformed */ }
            }
          }
          if (!controller.signal.aborted) { await loadFeed(); await wait(1000); }
        } catch (err: any) {
          if (err.name !== 'AbortError') console.warn('[sse] error:', err.message);
          if (controller.signal.aborted) break;
          await wait(backoff);
          backoff = Math.min(backoff * 2, 10_000);
        }
      }
    })();

    return () => controller.abort();
  }, [accessToken, loadFeed, handleEvent]);

  // ── Unsubscribe job cleanup ─────────────────────────────────────────
  useEffect(() => {
    const done = unsubscribeJobs.filter(j => j.status === 'done');
    if (done.length === 0) return;
    const t = setTimeout(() => setUnsubscribeJobs(prev => prev.filter(j => j.status !== 'done')), 5000);
    return () => clearTimeout(t);
  }, [unsubscribeJobs]);

  useEffect(() => {
    const errored = unsubscribeJobs.filter(j => j.status === 'error');
    if (errored.length === 0) return;
    const t = setTimeout(() => setUnsubscribeJobs(prev => prev.filter(j => j.status !== 'error')), 12000);
    return () => clearTimeout(t);
  }, [unsubscribeJobs]);

  const pollUnsubStatus = useCallback(async (token: string, messageId: string) => {
    if (activePolls.current.has(messageId)) return;
    activePolls.current.add(messageId);
    try {
      const deadline = Date.now() + 90_000;
      while (Date.now() < deadline) {
        const status = await fetchUnsubscribeStatus(token, messageId);
        if (status) {
          setUnsubscribeJobs(prev => {
            const exists = prev.find(j => j.messageId === messageId);
            return exists ? prev.map(j => j.messageId === messageId ? status : j) : [...prev, status];
          });
          if (status.status === 'done' || status.status === 'error') return;
        }
        await new Promise(r => setTimeout(r, 1500));
      }
    } finally {
      activePolls.current.delete(messageId);
    }
  }, []);

  // ── Actions ─────────────────────────────────────────────────────────

  const startUnsubscribe = useCallback((m: MessageRecord) => {
    if (!accessToken || !m.unsubscribeUrl) return;
    setUnsubscribeJobs(prev => {
      if (prev.find(j => j.messageId === m.messageId)) return prev;
      return [...prev, {
        messageId: m.messageId,
        senderName: m.fromName || m.fromEmail,
        status: 'queued',
        message: 'Starting unsubscribe…',
      }];
    });
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(() => {});
    requestUnsubscribe(accessToken, m.messageId, m.unsubscribeUrl, m.fromName || m.fromEmail)
      .then(result => {
        if (!result.ok) {
          setUnsubscribeJobs(prev => prev.map(j =>
            j.messageId === m.messageId ? { ...j, status: 'error', message: result.error ?? 'Failed' } : j
          ));
        } else {
          // A refreshed token means the original expired mid-request; adopt it
          // so the status poll and everything after it stay authorised.
          const token = result.refreshedToken ?? accessToken;
          if (result.refreshedToken) setAccessToken(result.refreshedToken);
          pollUnsubStatus(token, m.messageId).catch(err => console.warn('[unsub] poll failed:', err));
        }
      });
  }, [accessToken, pollUnsubStatus]);

  const archiveMessage = useCallback((m: MessageRecord) => {
    if (!accessToken) return;
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
    // Archive == mark read for this MVP; leaves a hook for a real archive
    // endpoint later. Layout animation on removal is handled by FeedCard's
    // Reanimated Layout.
    setFeedMessages(prev => prev.filter(x => x.messageId !== m.messageId));
    markAsRead(accessToken, m.messageId).catch(err => console.error('[read]', err));
  }, [accessToken]);

  const openDiscuss = useCallback((m: MessageRecord) => {
    setDiscussFor(m.messageId);
    trackAction('discuss_tapped', { feed_mode: mode });
  }, [mode]);

  const sendDiscussMessage = useCallback(async (text: string) => {
    if (!discussFor) return;
    const userMsg: DiscussMessage = { id: `u-${Date.now()}`, role: 'user', content: text };
    setDiscussMessages(prev => ({
      ...prev,
      [discussFor]: [...(prev[discussFor] ?? []), userMsg],
    }));
    // TODO: wire to /discuss endpoint. Until then, land a friendly placeholder.
    const stubId = `a-${Date.now()}`;
    setDiscussMessages(prev => ({
      ...prev,
      [discussFor]: [...(prev[discussFor] ?? []), {
        id: stubId,
        role: 'ai',
        content: 'Discuss is wired up here — the backend prompt lands next. In the meantime, this is where the model would answer.',
      }],
    }));
  }, [discussFor]);

  const buildOverflowItems = useCallback((m: MessageRecord): OverflowItem[] => {
    const items: OverflowItem[] = [];
    if (m.unsubscribeUrl) items.push({ key: 'unsub', label: 'Unsubscribe', icon: 'xmark', onPress: () => startUnsubscribe(m) });
    items.push({ key: 'save', label: 'Save', icon: 'bookmark', onPress: () => {} });
    items.push({ key: 'mute', label: 'Mute thread', icon: 'eye.slash', onPress: () => {} });
    items.push({ key: 'block', label: 'Block sender', icon: 'lock', destructive: true, onPress: () => {} });
    items.push({ key: 'report', label: 'Report scam', icon: 'flag', destructive: true, onPress: () => {} });
    return items;
  }, [startUnsubscribe]);

  const onRefresh = useCallback(async () => {
    if (!accessToken) return;
    setRefreshing(true);
    Haptics.selectionAsync().catch(() => {});
    try {
      await loadFeed();
    } finally {
      // Hold the affordance 300ms so refresh reads as an event, not a flicker.
      setTimeout(() => setRefreshing(false), 300);
    }
  }, [accessToken, loadFeed]);

  // ── Mode switching ──────────────────────────────────────────────────
  const onModeChange = useCallback(async (m: FeedMode) => {
    setMode(m);
    trackAction('mode_tapped', { mode: m });
    if (m === 'all-mail' && accessToken && allMail.length === 0) {
      setLoadingAllMail(true);
      try {
        const { cards, nextCursor } = await fetchAllMail(accessToken);
        setAllMail(cards);
        setAllMailCursor(nextCursor);
      } catch (err) {
        console.error('[all-mail] fetch failed:', err);
      } finally {
        setLoadingAllMail(false);
      }
    }
  }, [accessToken, allMail.length]);

  const loadMoreAllMail = useCallback(async () => {
    if (!accessToken || !allMailCursor || loadingAllMail) return;
    setLoadingAllMail(true);
    try {
      const { cards, nextCursor } = await fetchAllMail(accessToken, allMailCursor);
      setAllMail(prev => [...prev, ...cards]);
      setAllMailCursor(nextCursor);
    } finally {
      setLoadingAllMail(false);
    }
  }, [accessToken, allMailCursor, loadingAllMail]);

  // ── Rerender every minute so relative times stay honest ─────────────
  const [, tick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => tick(t => t + 1), 60_000);
    return () => clearInterval(id);
  }, []);

  // ── Current dataset ─────────────────────────────────────────────────
  const activeMessages = mode === 'feed' ? feedMessages : allMail;
  const unreadCount = feedMessages.filter(m => m.requiresAttention).length;
  // Zero-shot first: if the server wrote a recap line, that's what the user
  // reads. The counted fallback only covers the gap before it arrives.
  const unreadLabel = useMemo(() => {
    if (mode !== 'feed') return undefined;
    if (feedMessages.length === 0) return undefined;
    if (recap?.summary) return recap.summary;
    if (unreadCount > 0) return `${unreadCount} waiting on you`;
    return `${feedMessages.length} in view`;
  }, [mode, feedMessages.length, unreadCount, recap]);

  const openThread = useCallback((m: MessageRecord) => {
    trackAction('card_tapped', { mode });
    router.push({
      pathname: '/email/[messageId]',
      params: {
        messageId:          m.messageId,
        fromName:           m.fromName,
        fromEmail:          m.fromEmail,
        avatarUri:          m.avatarUri ?? '',
        avatarFallbackText: m.avatarFallbackText,
        subject:            m.subject,
        summary:            m.summary ?? '',
        snippet:            m.snippet,
        internalDate:       String(m.internalDate),
        heroImageUrl:       m.heroImageUrl ?? '',
        heroImageBgColor:   m.heroImageBgColor ?? '',
      },
    } as any);
  }, [mode, router]);

  const activeOverflow = overflowFor && activeMessages.find(m => m.messageId === overflowFor);
  const activeDiscuss  = discussFor  && activeMessages.find(m => m.messageId === discussFor);

  const renderItem = ({ item: m }: { item: MessageRecord }) => (
    <FeedCard
      sender={{
        name:  m.fromName || m.fromEmail.split('@')[0],
        email: m.fromEmail,
        avatarUri: m.avatarUri,
        avatarFallbackText: m.avatarFallbackText,
      }}
      kind={deriveKind(m)}
      status={deriveStatus(m)}
      headline={m.quote}
      body={m.summary}
      timestamp={relativeTime(m.internalDate)}
      unread={m.labelIds?.includes('UNREAD') ?? true}
      loading={m.aiStatus !== 'done' && m.aiStatus !== 'error'}
      isNew={newIds.has(m.messageId)}
      onOpen={() => openThread(m)}
      onReply={() => openThread(m)}
      onDiscuss={() => openDiscuss(m)}
      onForward={() => openThread(m)}
      onSave={() => {}}
      onArchive={() => archiveMessage(m)}
      onUnsubscribe={() => startUnsubscribe(m)}
      onOverflow={() => setOverflowFor(m.messageId)}
    />
  );

  // ── Render ──────────────────────────────────────────────────────────
  return (
    <View style={styles.root}>
      <StatusBar barStyle="light-content" backgroundColor={Theme.bg} />
      <SafeAreaView style={styles.safe} edges={['top']}>
        <FeedHeader
          scrollY={scrollY}
          mode={mode}
          onModeChange={onModeChange}
          unreadLabel={unreadLabel}
        />

        {!accessToken ? (
          <EmptyState
            icon="envelope"
            title="Connect your inbox"
            detail="Sign in with Google to turn your mail into a feed you can actually read."
            cta={request ? { label: 'Connect Gmail', onPress: () => promptAsync() } : undefined}
          />
        ) : activeMessages.length === 0 ? (
          mode === 'feed' ? (
            <CaughtUp
              line={userName ? `You're caught up, ${userName}.` : "You're caught up."}
              detail="Come back when something needs you."
            />
          ) : loadingAllMail ? (
            <View style={styles.spinner}><ActivityIndicator color={Theme.textSecondary} /></View>
          ) : (
            <EmptyState
              icon="envelope"
              title="All mail is empty"
              detail="Nothing has been synced here yet."
            />
          )
        ) : (
          <AnimatedFlatList
            data={activeMessages as any}
            keyExtractor={(item: any) => (item as MessageRecord).messageId}
            renderItem={renderItem as any}
            onScroll={onScroll}
            scrollEventThrottle={16}
            refreshControl={
              <RefreshControl
                refreshing={refreshing}
                onRefresh={onRefresh}
                tintColor={Theme.textSecondary}
                progressBackgroundColor={Theme.surface}
              />
            }
            contentContainerStyle={styles.list}
            ItemSeparatorComponent={() => <View style={styles.separator} />}
            onEndReached={mode === 'all-mail' ? loadMoreAllMail : undefined}
            onEndReachedThreshold={0.5}
            ListFooterComponent={
              mode === 'all-mail' && allMailCursor ? (
                <View style={styles.footer}>
                  {loadingAllMail
                    ? <ActivityIndicator color={Theme.textSecondary} />
                    : <Pressable onPress={loadMoreAllMail} style={styles.footerBtn}>
                        <Text style={styles.footerLabel}>Load more</Text>
                      </Pressable>}
                </View>
              ) : mode === 'feed' ? <CaughtUp line={null} /> : null
            }
          />
        )}
      </SafeAreaView>

      <UnsubscribeToast jobs={unsubscribeJobs} />

      <OverflowMenu
        visible={!!activeOverflow}
        onClose={() => setOverflowFor(null)}
        items={activeOverflow ? buildOverflowItems(activeOverflow) : []}
        title={activeOverflow ? (activeOverflow.fromName || activeOverflow.fromEmail) : undefined}
      />

      <DiscussSheet
        visible={!!activeDiscuss}
        onClose={() => setDiscussFor(null)}
        context={activeDiscuss ? {
          messageId: activeDiscuss.messageId,
          senderName: activeDiscuss.fromName || activeDiscuss.fromEmail,
          headline: activeDiscuss.quote,
        } : null}
        onSend={sendDiscussMessage}
        messages={discussFor ? (discussMessages[discussFor] ?? []) : []}
        proactive={activeDiscuss && activeDiscuss.summary
          ? `Here's the short of it: ${activeDiscuss.summary}`
          : null}
      />
    </View>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: Theme.bg,
  },
  safe: {
    flex: 1,
    backgroundColor: Theme.bg,
  },
  list: {
    paddingBottom: Spacing['3xl'],
  },
  separator: {
    height: 0, // separation is baked into the card's bottom pad
  },
  spinner: {
    padding: Spacing.xl,
    alignItems: 'center',
  },
  footer: {
    padding: Spacing.xl,
    alignItems: 'center',
  },
  footerBtn: {
    padding: Spacing.md,
  },
  footerLabel: {
    color: Theme.textSecondary,
  },
});
