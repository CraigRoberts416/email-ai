import EmailCard from '@/components/EmailCard';
import { GOOGLE_IOS_CLIENT_ID } from '@/constants/auth';
import { Colors, Radius, Spacing, Typography } from '@/constants/theme';
import * as Google from 'expo-auth-session/providers/google';
import { useEffect, useState } from 'react';
import { Linking, Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';

// ─── Gmail helpers ────────────────────────────────────────────────────────

const BACKEND_BASE_URL = 'http://localhost:3001';

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
        console.log('[gmail] fetching profile with access_token:', accessToken);

        const profileRes = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/profile', {
          headers: { Authorization: `Bearer ${accessToken}` },
        });
        const profileJson = await profileRes.json();
        console.log('[gmail] profile:', JSON.stringify(profileJson, null, 2));
      } catch (err) {
        console.error('[auth] token exchange failed:', err);
      }
    };

    exchangeToken();
  }, [response]);

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.content}>
        <Pressable
          style={({ pressed }) => [styles.connectBtn, pressed && styles.connectBtnPressed]}
          onPress={() => promptAsync()}
          disabled={!request}
        >
          <Text style={styles.connectLabel}>Connect Gmail</Text>
        </Pressable>
        <Pressable
          style={({ pressed }) => [styles.connectBtn, pressed && styles.connectBtnPressed]}
          onPress={async () => {
            if (!accessToken) return;
            setLoadingEmails(true);
            setCards([]);
            try {
              const listRes = await fetch(
                'https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=10',
                { headers: { Authorization: `Bearer ${accessToken}` } }
              );
              const listJson = await listRes.json();
              if (!listRes.ok) {
                console.error('[gmail] list error:', JSON.stringify(listJson, null, 2));
                return;
              }

              const ids: string[] = (listJson.messages ?? []).slice(0, 5).map((m: any) => m.id);

              const emails = await Promise.all(
                ids.map(async (id) => {
                  const msgRes = await fetch(
                    `https://gmail.googleapis.com/gmail/v1/users/me/messages/${id}?format=full`,
                    { headers: { Authorization: `Bearer ${accessToken}` } }
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
                    { headers: { Authorization: `Bearer ${accessToken}` } }
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
                    timestamp: meta ? formatRelativeTime(meta.date) : '',
                    threadMessageCount: meta ? (threadCounts[meta.threadId] ?? 1) : 1,
                  };
                  console.log('[interpret-single] card received:', card.id, card.senderName);
                  setCards(prev => [...prev, enriched]);
                } catch (err) {
                  console.error('[interpret-single] failed for', email.id, err);
                }
              }
            } catch (err) {
              console.error('[get-emails] fetch failed:', err);
            } finally {
              setLoadingEmails(false);
            }
          }}
          disabled={!accessToken || loadingEmails}
        >
          <Text style={styles.connectLabel}>{loadingEmails ? 'Loading…' : 'Get Emails'}</Text>
        </Pressable>
        {cards.map((card, i) => (
          <View key={card.id} style={i > 0 ? { marginTop: Spacing.sm } : undefined}>
            <EmailCard
              sender={{
                name: card.senderName,
                email: card.senderEmail,
                avatarUri: card.avatarUri ?? undefined,
                avatarFallbackText: card.avatarFallbackText,
              }}
              content={{
                contentType: 'structured',
                headline: card.quote,
                subtitle: card.subject,
                body: card.summary,
                cta: card.action && card.actionUrl
                  ? { label: card.action, onPress: () => Linking.openURL(card.actionUrl) }
                  : undefined,
                actionLabel: card.action && !card.actionUrl ? card.action : undefined,
              }}
              timestamp={card.timestamp}
              threadMessageCount={card.threadMessageCount}
              actions={{ aiSuggestionCount: 0 }}
            />
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
  connectLabel: {
    ...Typography.bodySm,
    color: Colors.light.textPrimary,
  },
});
