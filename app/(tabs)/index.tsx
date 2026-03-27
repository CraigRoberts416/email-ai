import EmailCard from '@/components/EmailCard';
import EmailCardSkeleton from '@/components/EmailCardSkeleton';
import InboxRecapHeader from '@/components/InboxRecapHeader';
import { GOOGLE_IOS_CLIENT_ID } from '@/constants/auth';
import { Colors, Radius, Spacing, Typography } from '@/constants/theme';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Google from 'expo-auth-session/providers/google';
import * as SecureStore from 'expo-secure-store';
import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState, Linking, Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';

// ─── Feed ─────────────────────────────────────────────────────────────────
//
// SLICE: Step 1 — real client → Render backend, user-scoped feed requests.
// The Google access token is sent as a Bearer header so the server can scope
// the feed to the authenticated user. Polling is gated on auth — no requests
// are made before the user has a valid token.
//
// NOT YET IMPLEMENTED:
//   - Seen state (Step 3): all cards are returned on every poll
//   - Unseen-only feed (Step 3): feed will filter to unseen cards
//   - Persistence (Step 2): server state resets on redeploy

const FEED_BASE_URL = 'https://email-ai-server.onrender.com';

type FeedCard = {
  id: string;
  status: 'pending' | 'ready';
  data: any | null;
  createdAt: number;
  emailDate: number; // epoch ms — real received time, drives feed order
};

async function fetchFeed(accessToken: string): Promise<{ cards: FeedCard[]; recap: any | null }> {
  const res = await fetch(`${FEED_BASE_URL}/feed`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error(`/feed returned ${res.status}`);
  return res.json();
}

// DEV ONLY ─────────────────────────────────────────────────────────────────
// Fetches the most recent Gmail message not already visible in the feed and
// sends it through the real Render /dev/ingest pipeline.
// Only called from __DEV__-gated UI, so this never ships in production builds.
//
// knownEmailIds: set of Gmail message IDs already present in feedCards,
// so repeated test taps use a fresh email each time.
async function devTriggerIngest(accessToken: string, knownEmailIds: Set<string>): Promise<string> {
  // Fetch the 5 most recent message IDs — enough to find one not yet in the feed
  const listRes = await fetch(
    'https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=5',
    { headers: { Authorization: `Bearer ${accessToken}` } }
  );
  if (!listRes.ok) throw new Error('Gmail list failed');
  const listJson = await listRes.json();
  const candidates: string[] = (listJson.messages ?? []).map((m: any) => m.id);
  if (candidates.length === 0) throw new Error('No messages found in inbox');

  // Prefer a message not already in the feed; fall back to the most recent
  const msgId = candidates.find(id => !knownEmailIds.has(id)) ?? candidates[0];

  // Fetch full message content
  const msgRes = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages/${msgId}?format=full`,
    { headers: { Authorization: `Bearer ${accessToken}` } }
  );
  if (!msgRes.ok) throw new Error('Gmail message fetch failed');
  const msg = await msgRes.json();

  // Clean with the same function used by the production ingestion path
  const email = cleanEmailForAI(msg);

  // POST to /dev/ingest — server immediately adds pending card, runs AI async
  const ingestRes = await fetch(`${FEED_BASE_URL}/dev/ingest`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email }),
  });
  if (!ingestRes.ok) throw new Error(`/dev/ingest returned ${ingestRes.status}`);
  const { id } = await ingestRes.json();
  return id;
}

// ─── Gmail helpers ────────────────────────────────────────────────────────

const BACKEND_BASE_URL = 'https://email-ai-server.onrender.com';

const AUTH_STORAGE_KEY = 'gmail_auth';
const CARDS_STORAGE_KEY = 'email_cards';
const RECAP_STORAGE_KEY = 'inbox_recap';
const USER_NAME_KEY = 'user_name';

async function saveCards(cards: any[]) {
  await AsyncStorage.setItem(CARDS_STORAGE_KEY, JSON.stringify(cards));
}

type RecapData = {
  greeting: string;
  summary: string;
  totalInView: number;
  requireAttention: number;
};

async function saveRecap(recap: RecapData) {
  await AsyncStorage.setItem(RECAP_STORAGE_KEY, JSON.stringify(recap));
}
async function loadRecap(): Promise<RecapData | null> {
  const raw = await AsyncStorage.getItem(RECAP_STORAGE_KEY);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

async function saveUserName(name: string) {
  await AsyncStorage.setItem(USER_NAME_KEY, name);
}
async function loadUserName(): Promise<string> {
  return (await AsyncStorage.getItem(USER_NAME_KEY)) ?? '';
}

function getTimeOfDay(): string {
  const h = new Date().getHours();
  if (h < 12) return 'morning';
  if (h < 17) return 'afternoon';
  return 'evening';
}

async function loadCards(): Promise<any[]> {
  const raw = await AsyncStorage.getItem(CARDS_STORAGE_KEY);
  if (!raw) return [];
  try { return JSON.parse(raw); } catch { return []; }
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

function getHeader(headers: { name: string; value: string }[], name: string): string {
  return headers.find(h => h.name.toLowerCase() === name.toLowerCase())?.value ?? '';
}

function decodeBody(data?: string): string {
  if (!data) return '';
  // Gmail uses base64url — normalise before decoding
  return atob(data.replace(/-/g, '+').replace(/_/g, '/'));
}

function extractBody(payload: any, mimeType: string): string {
  if (payload.mimeType === mimeType && payload.body?.data) {
    return decodeBody(payload.body.data);
  }
  for (const part of payload.parts ?? []) {
    const result = extractBody(part, mimeType);
    if (result) return result;
  }
  return '';
}

function cleanHtml(html: string): string {
  return html
    .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, '') // remove script/style blocks
    .replace(/<[^>]+>/g, ' ')                              // strip tags
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, ' ')                                  // collapse whitespace
    .trim();
}

type StructuredLink = { text: string; url: string; context: string | null };

function stripTags(s: string): string {
  return s.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
}

function extractStructuredLinks(html: string): StructuredLink[] {
  const results: StructuredLink[] = [];
  const seen = new Set<string>();
  const anchorRegex = /<a[^>]+href="(https?:\/\/[^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = anchorRegex.exec(html)) !== null) {
    const url = match[1];
    if (seen.has(url)) continue;
    seen.add(url);
    const text = stripTags(match[2]);
    if (!text || text.length < 2) continue;
    const start = Math.max(0, match.index - 100);
    const end = Math.min(html.length, match.index + match[0].length + 100);
    const surrounding = stripTags(html.slice(start, end));
    const contextRaw = surrounding.replace(text, '').trim().slice(0, 120);
    const context = contextRaw.length > 4 ? contextRaw : null;
    results.push({ text, url, context });
  }
  return results;
}

const FREE_MAIL_DOMAINS = new Set([
  'gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com',
  'icloud.com', 'live.com', 'msn.com', 'ymail.com',
]);

const SUSPICIOUS_SUBJECT_PATTERNS: { label: string; pattern: RegExp }[] = [
  { label: 'urgency',  pattern: /urgent|immediately|action required|act now|response required/i },
  { label: 'threat',   pattern: /suspended|account.*(closed|terminated|locked|disabled)/i },
  { label: 'prize',    pattern: /you('ve| have) won|winner|claim your (prize|reward|gift)/i },
  { label: 'verify',   pattern: /verify your (account|identity|email|information)/i },
  { label: 'unusual',  pattern: /unusual (activity|sign.?in|access)/i },
];

const GENERIC_GREETING = /^(dear (customer|user|account holder|member|friend|sir|madam)|hello (there|friend)|greetings)/i;

function parseSender(from: string): { name: string; email: string; domain: string } {
  const match = from.match(/^(.*?)\s*<([^>]+)>$/);
  const email = match ? match[2].trim() : from.trim();
  const name = match ? match[1].replace(/^"|"$/g, '').trim() : email;
  const domain = email.split('@')[1] ?? '';
  return { name, email, domain };
}

function hasAttachmentParts(payload: any): boolean {
  if (payload.filename && payload.filename.length > 0) return true;
  for (const part of payload.parts ?? []) {
    if (hasAttachmentParts(part)) return true;
  }
  return false;
}

function cleanEmailForAI(msg: any) {
  const headers = msg.payload?.headers ?? [];
  const from = getHeader(headers, 'From');
  const sender = parseSender(from);
  const replyToRaw = getHeader(headers, 'Reply-To');
  const replyTo = replyToRaw ? parseSender(replyToRaw).email : null;
  const replyToDomain = replyTo ? (replyTo.split('@')[1] ?? '') : null;
  const subject = getHeader(headers, 'Subject');
  const plainText = extractBody(msg.payload, 'text/plain');
  const htmlRaw = extractBody(msg.payload, 'text/html');
  const htmlText = cleanHtml(htmlRaw);
  const structuredLinks = extractStructuredLinks(htmlRaw);
  const readableText = (plainText || htmlText).trimStart();

  const links = structuredLinks.map(l => l.url);

  const unsubscribePresent =
    !!getHeader(headers, 'List-Unsubscribe') ||
    /unsubscribe/i.test(plainText) ||
    /unsubscribe/i.test(htmlRaw);

  const freeMailDomain = FREE_MAIL_DOMAINS.has(sender.domain.toLowerCase());

  const replyToMismatch =
    !!replyTo &&
    !!replyToDomain &&
    replyToDomain.toLowerCase() !== sender.domain.toLowerCase();

  const suspiciousSubjectHints = SUSPICIOUS_SUBJECT_PATTERNS
    .filter(({ pattern }) => pattern.test(subject))
    .map(({ label }) => label);

  const greetingGeneric = GENERIC_GREETING.test(readableText.slice(0, 80));

  const hasAttachments = hasAttachmentParts(msg.payload);

  return {
    id: msg.id,
    threadId: msg.threadId,
    sender: { ...sender, replyTo },
    subject,
    date: msg.internalDate ?? getHeader(headers, 'Date'),
    snippet: msg.snippet ?? '',
    body: {
      plainText,
      htmlText,
    },
    signals: {
      links,
      structuredLinks,
      unsubscribePresent,
      freeMailDomain,
      replyToMismatch,
      suspiciousSubjectHints,
      greetingGeneric,
      hasAttachments,
    },
  };
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
  const [cards, setCards] = useState<any[]>([]);
  const [loadingEmails, setLoadingEmails] = useState(false);
  const [userName, setUserName] = useState('');
  const [recap, setRecap] = useState<RecapData | null>(null);

  // ── Feed state ────────────────────────────────────────────────────────
  const [feedCards, setFeedCards] = useState<FeedCard[]>([]);
  const [loadingDevIngest, setLoadingDevIngest] = useState(false);

  const pollFeed = useCallback(async () => {
    // Gate on auth — do not hit the server until the user has a valid token.
    // accessToken is restored from SecureStore on mount, so the first poll
    // fires shortly after launch once auth is confirmed.
    if (!accessToken) return;
    try {
      const { cards: incoming, recap: incomingRecap } = await fetchFeed(accessToken);
      // Merge by id so cards update in place: pending → ready without positional jump.
      setFeedCards(prev => {
        const map = new Map(prev.map(c => [c.id, c]));
        for (const card of incoming) map.set(card.id, card);
        return Array.from(map.values()).sort((a, b) => {
          const diff = b.emailDate - a.emailDate;
          return diff !== 0 ? diff : b.createdAt - a.createdAt;
        });
      });
      // Recap is user-scoped and returned from the same feed state.
      // It is a session intro — set it once and do not update it mid-session.
      if (incomingRecap) setRecap(incomingRecap);
    } catch (err) {
      console.warn('[feed] poll failed:', err);
    }
  }, [accessToken]);

  // Fetch on mount, then every 12 seconds.
  // The interval restarts automatically if accessToken changes (user logs in).
  useEffect(() => {
    pollFeed();
    const id = setInterval(pollFeed, 12_000);
    return () => clearInterval(id);
  }, [pollFeed]);

  // DEV ONLY — handler for the in-app ingestion trigger button
  const handleDevIngest = useCallback(async () => {
    if (!accessToken) return;
    // Build the set of Gmail message IDs already visible in the feed,
    // so the trigger prefers a fresh email on each tap.
    const knownEmailIds = new Set<string>(
      feedCards.flatMap(c => (c.data?.emailId ? [c.data.emailId as string] : []))
    );
    setLoadingDevIngest(true);
    try {
      const cardId = await devTriggerIngest(accessToken, knownEmailIds);
      console.log('[dev/ingest] pending card id:', cardId);
      await pollFeed(); // immediate poll so skeleton appears without waiting 12s
    } catch (err) {
      console.error('[dev/ingest] trigger failed:', err);
    } finally {
      setLoadingDevIngest(false);
    }
  }, [accessToken, feedCards, pollFeed]);

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
            } else {
              await SecureStore.deleteItemAsync(AUTH_STORAGE_KEY);
              console.log('[auth] refresh failed, cleared stored session');
            }
          }
        } else {
          setAccessToken(stored.accessToken);
          console.log('[auth] session restored from storage');
        }
      } catch (err) {
        console.error('[auth] restore error:', err);
      }
    })();
  }, []);

  // Restore cached cards on launch
  useEffect(() => {
    console.log('[cache] restore effect mounting');
    (async () => {
      try {
        const cached = await loadCards();
        if (cached.length > 0) {
          setCards(cached);
          console.log('[cache] restored', cached.length, 'cards');
        } else {
          console.log('[cache] no cached cards found');
        }
      } catch (err) {
        console.error('[cache] restore error:', err);
      }
    })();
  }, []);

  // Restore recap and user name on launch
  useEffect(() => {
    loadRecap().then(r => { if (r) setRecap(r); });
    loadUserName().then(n => { if (n) setUserName(n); });
  }, []);

  const runSync = useCallback(async () => {
    console.log('[runSync] called — accessToken:', !!accessToken, 'loadingEmails:', loadingEmails);
    if (!accessToken) { console.log('[runSync] exit: no accessToken'); return; }
    if (loadingEmails) { console.log('[runSync] exit: already loading'); return; }
    setLoadingEmails(true);
    // Snapshot cards at sync start — used consistently for dedup and combine
    const existingCards = cards;
    try {
      // Refresh token if expired before making Gmail requests
      let currentToken = accessToken;
      const stored = await loadAuth();
      if (stored && stored.refreshToken && Date.now() >= stored.expiresAt - 60_000) {
        console.log('[auth] token expired before fetch, refreshing...');
        const refreshed = await refreshAccessToken(stored.refreshToken);
        if (refreshed) {
          await saveAuth(refreshed.accessToken, stored.refreshToken, refreshed.expiresAt);
          setAccessToken(refreshed.accessToken);
          currentToken = refreshed.accessToken;
        }
      }

      const listRes = await fetch(
        'https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=10',
        { headers: { Authorization: `Bearer ${currentToken}` } }
      );
      const listJson = await listRes.json();
      if (!listRes.ok) {
        console.error('[gmail] list error:', JSON.stringify(listJson, null, 2));
        return;
      }

      const existingIds = new Set(existingCards.map((c: any) => c.id));
      const allIds: string[] = (listJson.messages ?? []).slice(0, 5).map((m: any) => m.id);
      const ids = allIds.filter(id => !existingIds.has(id));
      if (ids.length === 0) {
        console.log('[sync] no new emails — recapping current feed');
        try {
          const recapRes = await fetch(`${BACKEND_BASE_URL}/session-recap`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              cards: existingCards.map((c: any) => ({
                senderName: c.senderName,
                subject: c.subject,
                summary: c.summary,
                action: c.action,
              })),
              userName,
              timeOfDay: getTimeOfDay(),
            }),
          });
          const { recap: recapData } = await recapRes.json();
          setRecap(recapData);
          await saveRecap(recapData);
        } catch (err) {
          console.error('[session-recap] failed:', err);
        }
        return;
      }
      console.log('[sync]', ids.length, 'new email(s) to process');

      const emails = await Promise.all(
        ids.map(async (id) => {
          const msgRes = await fetch(
            `https://gmail.googleapis.com/gmail/v1/users/me/messages/${id}?format=full`,
            { headers: { Authorization: `Bearer ${currentToken}` } }
          );
          const msg = await msgRes.json();
          return cleanEmailForAI(msg);
        })
      );

      console.log('[gmail] cleanEmailForAI first email:', JSON.stringify(emails[0], null, 2));

      // Build local metadata map and fetch thread counts in parallel with backend call
      const metaById: Record<string, { date: string; threadId: string }> = {};
      emails.forEach((e: any) => { metaById[e.id] = { date: e.date, threadId: e.threadId }; });

      const uniqueThreadIds = [...new Set(emails.map((e: any) => e.threadId as string))];

      // Await thread counts before streaming — fast metadata call, always done before first AI response
      const threadCountEntries = await Promise.all(uniqueThreadIds.map(async (threadId) => {
        try {
          const res = await fetch(
            `https://gmail.googleapis.com/gmail/v1/users/me/threads/${threadId}?format=metadata`,
            { headers: { Authorization: `Bearer ${currentToken}` } }
          );
          const json = await res.json();
          return [threadId, json.messages?.length ?? 1] as [string, number];
        } catch {
          return [threadId, 1] as [string, number];
        }
      }));
      const threadCounts = Object.fromEntries(threadCountEntries);
      console.log('[thread-counts]', JSON.stringify(threadCounts));
      console.log('[email-meta] first:', JSON.stringify(Object.values(metaById)[0]));

      // Process emails sequentially — append each card as it arrives
      const incomingCards: any[] = [];
      for (const email of emails) {
        console.log('[interpret-single] requesting', email.id, email.subject);
        try {
          const res = await fetch(`${BACKEND_BASE_URL}/interpret-single`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email }),
          });
          const { card } = await res.json();
          const meta = metaById[card.id];
          const enriched = {
            ...card,
            threadMessageCount: meta ? (threadCounts[meta.threadId] ?? 1) : 1,
          };
          console.log('[interpret-single] card received:', card.id, card.senderName);
          incomingCards.push(enriched);
        } catch (err) {
          console.error('[interpret-single] failed for', email.id, err);
          const meta = metaById[email.id];
          const fallback = {
            id: email.id,
            senderName: email.sender.name,
            senderEmail: email.sender.email,
            subject: email.subject,
            date: email.date,
            threadId: email.threadId,
            avatarUri: null,
            avatarFallbackText: (email.sender.name || email.sender.email || '?').charAt(0).toUpperCase(),
            quote: 'Unable to extract quote',
            summary: email.snippet || 'Unable to summarize email.',
            action: null,
            actionUrl: null,
            threadMessageCount: meta ? (threadCounts[meta.threadId] ?? 1) : 1,
          };
          console.log('[interpret-single] rendering fallback card for', email.id);
          incomingCards.push(fallback);
        }
      }
      if (incomingCards.length > 0) {
        const combined = [...incomingCards, ...existingCards];
        setCards(combined);
        await saveCards(combined);
        try {
          const recapRes = await fetch(`${BACKEND_BASE_URL}/session-recap`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              cards: combined.map((c: any) => ({
                senderName: c.senderName,
                subject: c.subject,
                summary: c.summary,
                action: c.action,
              })),
              userName,
              timeOfDay: getTimeOfDay(),
            }),
          });
          const { recap: recapData } = await recapRes.json();
          setRecap(recapData);
          await saveRecap(recapData);
        } catch (err) {
          console.error('[session-recap] failed:', err);
        }
      }
    } catch (err) {
      console.error('[get-emails] fetch failed:', err);
    } finally {
      setLoadingEmails(false);
    }
  }, [accessToken, cards, loadingEmails, userName]);

  // Keep a ref so the AppState listener always calls the latest runSync
  const syncRef = useRef(runSync);
  useEffect(() => { syncRef.current = runSync; }, [runSync]);

  // Auto-sync whenever the app comes to the foreground
  useEffect(() => {
    const sub = AppState.addEventListener('change', nextState => {
      console.log('[appstate] change →', nextState);
      if (nextState === 'active') {
        console.log('[appstate] foregrounded — calling syncRef.current()');
        syncRef.current();
      }
    });
    return () => sub.remove();
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

        const accessToken = json.access_token;
        setAccessToken(accessToken);
        const existingAuth = await loadAuth();
        const refreshToken = json.refresh_token ?? existingAuth?.refreshToken ?? null;
        await saveAuth(accessToken, refreshToken, Date.now() + json.expires_in * 1000);
        console.log('[auth] refresh_token present:', !!refreshToken);
        console.log('[auth] tokens saved to secure storage');
        console.log('[gmail] fetching profile with access_token:', accessToken);

        const profileRes = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/profile', {
          headers: { Authorization: `Bearer ${accessToken}` },
        });
        const profileJson = await profileRes.json();
        console.log('[gmail] profile:', JSON.stringify(profileJson, null, 2));

        const userInfoRes = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
          headers: { Authorization: `Bearer ${accessToken}` },
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
        <Pressable
          style={({ pressed }) => [styles.connectBtn, pressed && styles.connectBtnPressed]}
          onPress={runSync}
          disabled={!accessToken || loadingEmails}
        >
          <Text style={styles.connectLabel}>{loadingEmails ? 'Loading…' : 'Get Emails'}</Text>
        </Pressable>
        {/* DEV ONLY — remove before launch */}
        <Pressable
          style={({ pressed }) => [styles.connectBtn, styles.devBtn, pressed && styles.connectBtnPressed]}
          onPress={handleDevIngest}
          disabled={!accessToken || loadingDevIngest}
        >
          <Text style={styles.connectLabel}>
            {loadingDevIngest ? 'Injecting…' : '[DEV] Ingest Latest Email'}
          </Text>
        </Pressable>
        {/* DEV ONLY — auth state diagnostic, remove before launch */}
        <Text style={styles.devStatus}>
          {accessToken ? `token: live (${accessToken.slice(0, 8)}…)` : 'token: none — tap Connect Gmail to re-authorise'}
        </Text>
        {feedCards.map((feedCard, i) => (
          <View key={feedCard.id} style={i > 0 ? { marginTop: Spacing.sm } : undefined}>
            {feedCard.status === 'pending' || !feedCard.data ? (
              <EmailCardSkeleton />
            ) : (
              <EmailCard
                sender={{
                  name: feedCard.data.senderName,
                  email: feedCard.data.senderEmail,
                  avatarUri: feedCard.data.avatarUri ?? undefined,
                  avatarFallbackText: feedCard.data.avatarFallbackText,
                }}
                content={{
                  contentType: 'structured',
                  headline: feedCard.data.quote,
                  subtitle: feedCard.data.subject,
                  body: feedCard.data.summary,
                  cta: feedCard.data.action && feedCard.data.actionUrl
                    ? { label: feedCard.data.action, onPress: () => Linking.openURL(feedCard.data.actionUrl) }
                    : undefined,
                  actionLabel: feedCard.data.action && !feedCard.data.actionUrl
                    ? feedCard.data.action
                    : undefined,
                }}
                timestamp={formatRelativeTime(feedCard.data.date)}
                threadMessageCount={feedCard.data.threadMessageCount}
                actions={{ aiSuggestionCount: 0 }}
              />
            )}
          </View>
        ))}
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
  devBtn: {
    borderWidth: 1,
    borderColor: Colors.light.textSecondary,
    borderStyle: 'dashed',
  },
  devStatus: {
    ...Typography.bodySm,
    color: Colors.light.textSecondary,
    textAlign: 'center',
    marginBottom: Spacing.lg,
  },
  connectLabel: {
    ...Typography.bodySm,
    color: Colors.light.textPrimary,
  },
});
