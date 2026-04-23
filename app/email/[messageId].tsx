import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import {
  Image,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { Colors, DmSansFonts, InterFonts, Radius, Spacing } from '@/constants/theme';

// ─── Types ────────────────────────────────────────────────────────────────

type ChatMessage = { role: 'user' | 'ai'; text: string };

// ─── Helpers ──────────────────────────────────────────────────────────────

function formatRelativeTime(dateStr: string): string {
  if (!dateStr) return '';
  const asMs = Number(dateStr);
  const date = isNaN(asMs) ? new Date(dateStr) : new Date(asMs);
  if (isNaN(date.getTime())) return '';
  const diffMs = Date.now() - date.getTime();
  const diffMins = Math.floor(diffMs / 60_000);
  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `${diffHours} hour${diffHours === 1 ? '' : 's'} ago`;
  const diffDays = Math.floor(diffHours / 24);
  if (diffDays === 1) return 'Yesterday';
  if (diffDays < 7) return `${diffDays} days ago`;
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

const DEFAULT_BG = '#0D1B3E';
const HERO_HEIGHT = 258;
const HERO_OVERLAP = 78;

// ─── EmailThreadCard ──────────────────────────────────────────────────────

function EmailThreadCard({
  fromName,
  avatarUri,
  avatarFallbackText,
  timestamp,
  body,
}: {
  fromName: string;
  fromEmail: string;
  avatarUri?: string;
  avatarFallbackText: string;
  timestamp: string;
  body: string;
}) {
  const [imgError, setImgError] = useState(false);
  return (
    <View style={cardStyles.card}>
      <View style={cardStyles.infoBlock}>
        <View style={cardStyles.senderRow}>
          <View style={cardStyles.avatarWrap}>
            {avatarUri && !imgError ? (
              <Image
                source={{ uri: avatarUri }}
                style={cardStyles.avatar}
                onError={() => setImgError(true)}
              />
            ) : (
              <View style={cardStyles.avatarFallback}>
                <Text style={cardStyles.avatarInitial}>
                  {(avatarFallbackText || fromName || '?').charAt(0).toUpperCase()}
                </Text>
              </View>
            )}
          </View>
          <Text style={cardStyles.senderName}>{fromName}</Text>
        </View>
        <View style={cardStyles.timeRow}>
          <IconSymbol name="clock" size={14} color={Colors.light.textSecondary} />
          <Text style={cardStyles.timeText}>{timestamp.toUpperCase()}</Text>
        </View>
      </View>
      <Text style={cardStyles.bodyText}>{body}</Text>
      <View style={cardStyles.actionBar}>
        <View style={cardStyles.actionsGroup}>
          <Pressable style={cardStyles.actionBtn} hitSlop={8}>
            <IconSymbol name="face.smiling" size={16} color={Colors.light.textPrimary} />
          </Pressable>
          <Pressable style={cardStyles.actionBtn} hitSlop={8}>
            <IconSymbol name="arrow.turn.up.left" size={16} color={Colors.light.textPrimary} />
          </Pressable>
          <Pressable style={cardStyles.actionBtn} hitSlop={8}>
            <IconSymbol name="arrow.turn.up.right" size={16} color={Colors.light.textPrimary} />
          </Pressable>
        </View>
        <View style={cardStyles.actionsGroup}>
          <Pressable style={cardStyles.actionBtn} hitSlop={8}>
            <IconSymbol name="bookmark" size={16} color={Colors.light.textPrimary} />
          </Pressable>
          <Pressable style={cardStyles.actionBtn} hitSlop={8}>
            <IconSymbol name="trash" size={16} color={Colors.light.textPrimary} />
          </Pressable>
        </View>
      </View>
    </View>
  );
}

const cardStyles = StyleSheet.create({
  card: {
    backgroundColor: Colors.light.background,
    borderRadius: Radius.lg,
    paddingHorizontal: 24,
    paddingVertical: 32,
    gap: Spacing.lg,
  },
  infoBlock: {
    gap: Spacing.sm,
  },
  senderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  avatarWrap: {
    width: 24,
    height: 24,
    borderRadius: Radius.round,
    borderWidth: 1,
    borderColor: Colors.light.border,
    overflow: 'hidden',
    flexShrink: 0,
  },
  avatar: {
    width: '100%',
    height: '100%',
  },
  avatarFallback: {
    width: '100%',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.light.surface,
  },
  avatarInitial: {
    fontFamily: InterFonts.regular,
    fontSize: 10,
    color: Colors.light.textSecondary,
  },
  senderName: {
    fontFamily: DmSansFonts.regular,
    fontSize: 16,
    fontWeight: '400' as const,
    color: Colors.light.textPrimary,
    letterSpacing: -0.32,
  },
  timeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,
  },
  timeText: {
    fontFamily: InterFonts.medium,
    fontSize: 12,
    fontWeight: '500' as const,
    color: Colors.light.textSecondary,
    letterSpacing: -0.12,
    lineHeight: 17,
  },
  bodyText: {
    fontFamily: InterFonts.regular,
    fontSize: 16,
    fontWeight: '400' as const,
    color: Colors.light.textPrimary,
    lineHeight: 22,
    letterSpacing: -0.32,
  },
  actionBar: {
    borderTopWidth: 1,
    borderTopColor: Colors.light.border,
    paddingTop: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  actionsGroup: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
  },
  actionBtn: {
    width: Spacing.lg,
    height: Spacing.lg,
    alignItems: 'center',
    justifyContent: 'center',
  },
});

// ─── Screen ───────────────────────────────────────────────────────────────

export default function OpenEmailScreen() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{
    messageId: string;
    fromName: string;
    fromEmail: string;
    avatarUri?: string;
    avatarFallbackText: string;
    subject: string;
    summary?: string;
    snippet: string;
    internalDate: string;
    heroImageUrl?: string;
    heroImageBgColor?: string;
  }>();

  const bgColor = params.heroImageBgColor || DEFAULT_BG;
  const hasHeroImage = !!params.heroImageUrl;
  const timestamp = formatRelativeTime(params.internalDate ?? '');

  const [headerAvatarError, setHeaderAvatarError] = useState(false);
  const [inputText, setInputText] = useState('');
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>([]);

  const handleSend = () => {
    const text = inputText.trim();
    if (!text) return;
    setChatMessages(prev => [...prev, { role: 'user', text }]);
    setInputText('');
    // AI response: wired to backend in a future step
  };

  return (
    <>
      <Stack.Screen options={{ headerShown: false }} />
      <View style={[styles.root, { backgroundColor: bgColor }]}>

        {/* Nav buttons — float over scroll content */}
        <View style={[styles.navRow, { top: insets.top + 10 }]}>
          <Pressable style={styles.navBtn} onPress={() => router.back()} hitSlop={8}>
            <IconSymbol name="chevron.left" size={20} color="white" />
          </Pressable>
          <Pressable style={styles.navBtn} hitSlop={8}>
            <IconSymbol name="ellipsis" size={20} color="white" />
          </Pressable>
        </View>

        <KeyboardAvoidingView
          style={styles.kav}
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        >
          <ScrollView style={styles.scroll} showsVerticalScrollIndicator={false}>

            {/* ── Hero ──────────────────────────────────────────────── */}
            <View style={styles.hero}>
              {hasHeroImage && (
                <Image
                  source={{ uri: params.heroImageUrl }}
                  style={StyleSheet.absoluteFill}
                  resizeMode="cover"
                />
              )}
            </View>

            {/* ── Header overlay (overlaps hero bottom) ─────────────── */}
            <View style={styles.headerOverlay}>

              {/* Sender + Go To Page row */}
              <View style={styles.senderRow}>
                <View style={styles.senderLeft}>
                  <View style={styles.headerAvatarWrap}>
                    {params.avatarUri && !headerAvatarError ? (
                      <Image
                        source={{ uri: params.avatarUri }}
                        style={styles.headerAvatar}
                        onError={() => setHeaderAvatarError(true)}
                      />
                    ) : (
                      <View style={styles.headerAvatarFallback}>
                        <Text style={styles.headerAvatarInitial}>
                          {(params.avatarFallbackText || params.fromName || '?').charAt(0).toUpperCase()}
                        </Text>
                      </View>
                    )}
                  </View>
                  <Text style={styles.headerSenderName}>{params.fromName}</Text>
                </View>
                <View style={styles.goToPageBtn}>
                  <Text style={styles.goToPageLabel}>GO TO PAGE</Text>
                </View>
              </View>

              {/* Subject */}
              <Text style={styles.subject}>{params.subject}</Text>

              {/* Thread count */}
              <View style={styles.threadCountRow}>
                <IconSymbol name="bubble.left.and.bubble.right" size={14} color={Colors.light.textSecondary} />
                <Text style={styles.threadCountText}>EMAIL THREAD</Text>
              </View>

              {/* AI Summary */}
              {!!params.summary && (
                <Text style={styles.summary}>{params.summary}</Text>
              )}
            </View>

            {/* ── Email cards ───────────────────────────────────────── */}
            <View style={styles.cards}>
              <EmailThreadCard
                fromName={params.fromName ?? ''}
                fromEmail={params.fromEmail ?? ''}
                avatarUri={params.avatarUri}
                avatarFallbackText={params.avatarFallbackText ?? ''}
                timestamp={timestamp}
                body={params.snippet ?? ''}
              />
            </View>

            {/* ── Chat messages ─────────────────────────────────────── */}
            {chatMessages.length > 0 && (
              <View style={styles.chatMessages}>
                {chatMessages.map((msg, i) =>
                  msg.role === 'user' ? (
                    <View key={i} style={styles.userBubble}>
                      <Text style={styles.userBubbleText}>{msg.text}</Text>
                    </View>
                  ) : (
                    <Text key={i} style={styles.aiResponse}>{msg.text}</Text>
                  )
                )}
              </View>
            )}

            <View style={{ height: 24 }} />
          </ScrollView>

          {/* ── Chat input ────────────────────────────────────────────── */}
          <View style={[styles.inputBar, { paddingBottom: Math.max(insets.bottom, 8) + 8 }]}>
            <View style={styles.inputPill}>
              <TextInput
                style={styles.inputField}
                placeholder="Ask about the thread"
                placeholderTextColor={Colors.light.textSecondary}
                value={inputText}
                onChangeText={setInputText}
                onSubmitEditing={handleSend}
                returnKeyType="send"
              />
            </View>
            <Pressable style={styles.sendBtn} onPress={handleSend} hitSlop={8}>
              <IconSymbol name="arrow.up.circle" size={24} color="white" />
            </Pressable>
          </View>
        </KeyboardAvoidingView>

      </View>
    </>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  kav: {
    flex: 1,
  },
  scroll: {
    flex: 1,
  },

  // Nav
  navRow: {
    position: 'absolute',
    left: 13,
    right: 13,
    zIndex: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  navBtn: {
    width: 40,
    height: 40,
    borderRadius: Radius.round,
    alignItems: 'center',
    justifyContent: 'center',
  },

  // Hero
  hero: {
    height: HERO_HEIGHT,
    overflow: 'hidden',
  },

  // Header overlay
  headerOverlay: {
    marginTop: -HERO_OVERLAP,
    paddingHorizontal: 32,
  },
  senderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 32,
  },
  senderLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  headerAvatarWrap: {
    width: 24,
    height: 24,
    borderRadius: Radius.round,
    borderWidth: 1,
    borderColor: Colors.light.border,
    overflow: 'hidden',
    flexShrink: 0,
  },
  headerAvatar: {
    width: '100%',
    height: '100%',
  },
  headerAvatarFallback: {
    width: '100%',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.2)',
  },
  headerAvatarInitial: {
    fontFamily: InterFonts.regular,
    fontSize: 10,
    color: 'white',
  },
  headerSenderName: {
    fontFamily: DmSansFonts.regular,
    fontSize: 16,
    fontWeight: '400' as const,
    color: 'white',
    letterSpacing: -0.32,
  },
  goToPageBtn: {
    borderWidth: 1,
    borderColor: Colors.light.border,
    borderRadius: Radius.md,
    paddingHorizontal: 16,
    paddingVertical: 4,
    opacity: 0.4,
  },
  goToPageLabel: {
    fontFamily: InterFonts.medium,
    fontSize: 12,
    fontWeight: '500' as const,
    color: 'white',
    letterSpacing: -0.24,
    textTransform: 'uppercase',
  },
  subject: {
    fontFamily: DmSansFonts.regular,
    fontSize: 28,
    fontWeight: '400' as const,
    lineHeight: 31,
    letterSpacing: -0.84,
    color: 'white',
    marginBottom: 20,
  },
  threadCountRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,
    marginBottom: 8,
  },
  threadCountText: {
    fontFamily: InterFonts.medium,
    fontSize: 12,
    fontWeight: '500' as const,
    color: Colors.light.textSecondary,
    letterSpacing: -0.12,
    textTransform: 'uppercase',
  },
  summary: {
    fontFamily: InterFonts.regular,
    fontSize: 16,
    fontWeight: '400' as const,
    color: 'white',
    lineHeight: 22,
    letterSpacing: -0.32,
    marginTop: 8,
    marginBottom: 8,
  },

  // Cards
  cards: {
    gap: Spacing.md,
    paddingHorizontal: Spacing.md,
    paddingTop: Spacing.xl,
  },

  // Chat
  chatMessages: {
    paddingHorizontal: Spacing.md,
    paddingTop: Spacing.md,
    gap: Spacing.md,
  },
  userBubble: {
    alignSelf: 'flex-end',
    backgroundColor: Colors.light.surface,
    borderRadius: Radius.lg,
    borderBottomRightRadius: 8,
    padding: Spacing.md,
    maxWidth: '75%',
  },
  userBubbleText: {
    fontFamily: InterFonts.regular,
    fontSize: 16,
    fontWeight: '400' as const,
    color: Colors.light.textPrimary,
    lineHeight: 22,
    letterSpacing: -0.32,
  },
  aiResponse: {
    fontFamily: InterFonts.regular,
    fontSize: 16,
    fontWeight: '400' as const,
    color: 'white',
    lineHeight: 22,
    letterSpacing: -0.32,
    paddingHorizontal: Spacing.sm,
  },

  // Input bar
  inputBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Spacing.md,
    paddingTop: Spacing.md,
    gap: Spacing.md,
  },
  inputPill: {
    flex: 1,
    height: 40,
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderRadius: Radius.round,
    paddingHorizontal: Spacing.md,
    justifyContent: 'center',
  },
  inputField: {
    fontFamily: InterFonts.regular,
    fontSize: 16,
    color: 'white',
    letterSpacing: -0.32,
  },
  sendBtn: {
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
