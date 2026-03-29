import EmailCard from '@/components/EmailCard';
import EmailCardSkeleton from '@/components/EmailCardSkeleton';
import InboxRecapHeader from '@/components/InboxRecapHeader';
import { GOOGLE_IOS_CLIENT_ID } from '@/constants/auth';
import { Colors, Radius, Spacing, Typography } from '@/constants/theme';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Google from 'expo-auth-session/providers/google';
import * as SecureStore from 'expo-secure-store';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Linking, Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';

// ─── Feed ─────────────────────────────────────────────────────────────────

const FEED_BASE_URL = 'https://email-ai-server.onrender.com';

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
  // Computed server-side
  avatarUri:         string | null;
  avatarFallbackText: string;
  // Only on All Mail cards from server
  interpreted?:      boolean;
};

async function fetchFeed(accessToken: string): Promise<{ cards: MessageRecord[] }> {
  const res = await fetch(`${FEED_BASE_URL}/feed`, {
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
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error(`/all-mail returned ${res.status}`);
  return res.json();
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
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [userName, setUserName] = useState('');
  const [recap] = useState<RecapData | null>(null);

  // ── Feed state ────────────────────────────────────────────────────────
  const [feedMessages, setFeedMessages] = useState<MessageRecord[]>([]);

  // ── All Mail state ────────────────────────────────────────────────────
  const [activeTab, setActiveTab] = useState<'feed' | 'allMail'>('feed');
  const [allMailMessages, setAllMailMessages] = useState<MessageRecord[]>([]);
  const [allMailCursor, setAllMailCursor] = useState<number | null>(null);
  const [loadingAllMail, setLoadingAllMail] = useState(false);
  const [allMailFetched, setAllMailFetched] = useState(false);

  // Reset All Mail cache when auth changes so a new user gets a fresh fetch
  useEffect(() => {
    setAllMailFetched(false);
    setAllMailMessages([]);
    setAllMailCursor(null);
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

    (async () => {
      try {
        const response = await fetch(`${FEED_BASE_URL}/feed/events`, {
          headers: { Authorization: `Bearer ${accessToken}` },
          signal: controller.signal,
        });
        if (!response.ok) { console.warn('[sse] connect failed:', response.status); return; }

        const reader = response.body?.getReader();
        if (!reader) return;

        const decoder = new TextDecoder();
        let buffer = '';

        while (true) {
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
              } else if (evtType === 'chunk') {
                // Streaming token — append to appropriate field
                const field = event.field as keyof MessageRecord;
                setFeedMessages(prev => prev.map(m => {
                  if (m.messageId !== messageId) return m;
                  const prev_val = m[field];
                  const appended = (typeof prev_val === 'string' ? prev_val : '') + event.chunk;
                  return { ...m, [field]: appended };
                }));
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
              }
            } catch { /* skip malformed event */ }
          }
        }

        // SSE disconnected — reload feed to catch any missed events
        if (!controller.signal.aborted) {
          loadFeed();
        }
      } catch (err: any) {
        if (err.name !== 'AbortError') console.warn('[sse] error:', err.message);
      }
    })();

    return () => controller.abort();
  }, [accessToken, loadFeed]);

  const handleTabChange = useCallback(async (tab: 'feed' | 'allMail') => {
    setActiveTab(tab);
    if (tab === 'allMail' && !allMailFetched && accessToken) {
      setLoadingAllMail(true);
      try {
        const { cards, nextCursor } = await fetchAllMail(accessToken);
        setAllMailMessages(cards);
        setAllMailCursor(nextCursor);
        setAllMailFetched(true);
      } catch (err) {
        console.error('[all-mail] fetch failed:', err);
      } finally {
        setLoadingAllMail(false);
      }
    }
  }, [allMailFetched, accessToken]);

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
              setAccessToken(refreshed.accessToken);
              console.log('[auth] session restored via refresh');
              // Re-register with backend so worker is running
              registerWithBackend(refreshed.accessToken, stored.refreshToken, refreshed.expiresAt);
            } else {
              await SecureStore.deleteItemAsync(AUTH_STORAGE_KEY);
              console.log('[auth] refresh failed, cleared stored session');
            }
          }
        } else {
          setAccessToken(stored.accessToken);
          console.log('[auth] session restored from storage');
          // Re-register with backend so worker is running (idempotent)
          if (stored.refreshToken) {
            registerWithBackend(stored.accessToken, stored.refreshToken, stored.expiresAt);
          }
        }
      } catch (err) {
        console.error('[auth] restore error:', err);
      }
    })();
  }, []);

  // Restore user name on launch
  useEffect(() => {
    loadUserName().then(n => { if (n) setUserName(n); });
  }, []);

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
        setAccessToken(newAccessToken);
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

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.content}>
        {recap && <InboxRecapHeader recap={recap} />}
        <Pressable
          style={({ pressed }) => [styles.connectBtn, pressed && styles.connectBtnPressed]}
          onPress={() => promptAsync()}
          disabled={!request}
        >
          <Text style={styles.connectLabel}>Connect Gmail</Text>
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
              Mail Feed
            </Text>
          </Pressable>
          <Pressable
            style={[styles.toggleBtn, activeTab === 'allMail' && styles.toggleBtnActive]}
            onPress={() => handleTabChange('allMail')}
          >
            <Text style={[styles.toggleLabel, activeTab === 'allMail' && styles.toggleLabelActive]}>
              All Mail
            </Text>
          </Pressable>
        </View>

        {/* ── Mail Feed ───────────────────────────────────────────── */}
        {activeTab === 'feed' && feedMessages.map((m, i) => (
          <View key={m.messageId} style={i > 0 ? { marginTop: Spacing.sm } : undefined}>
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
                  actionLabel: m.action && !m.actionUrl
                    ? m.action
                    : undefined,
                }}
                loading={m.aiStatus !== 'done'}
                timestamp={formatRelativeTime(String(m.internalDate))}
                actions={{
                  aiSuggestionCount: 0,
                  onDelete: accessToken
                    ? () => markAsRead(accessToken, m.messageId).catch(err =>
                        console.error('[read] markAsRead failed:', err)
                      )
                    : undefined,
                }}
              />
            )}
          </View>
        ))}

        {/* ── All Mail ────────────────────────────────────────────── */}
        {activeTab === 'allMail' && loadingAllMail && allMailMessages.length === 0 && (
          <EmailCardSkeleton />
        )}
        {activeTab === 'allMail' && allMailMessages.map((m, i) => {
          // AI fields take priority; subject + snippet are the non-interpreted fallback.
          const headline = m.quote   || m.subject || null;
          const body     = m.summary || (m.snippet ? m.snippet + ' See more...' : null);
          return (
            <View key={m.messageId} style={i > 0 ? { marginTop: Spacing.sm } : undefined}>
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
                loading={false}
                timestamp={formatRelativeTime(String(m.internalDate))}
                actions={{ aiSuggestionCount: 0 }}
              />
            </View>
          );
        })}
        {activeTab === 'allMail' && allMailFetched && allMailCursor && (
          <Pressable
            style={({ pressed }) => [styles.connectBtn, pressed && styles.connectBtnPressed, { marginTop: Spacing.sm }]}
            onPress={handleLoadMoreAllMail}
            disabled={loadingAllMail}
          >
            <Text style={styles.connectLabel}>{loadingAllMail ? 'Loading…' : 'Load More'}</Text>
          </Pressable>
        )}
      </ScrollView>
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
