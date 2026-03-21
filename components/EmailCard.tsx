import React, { useEffect, useState } from 'react';
import {
  Image,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { Colors, InterFonts, Radius, Spacing, Typography } from '@/constants/theme';

// ─── Types ────────────────────────────────────────────────────────────────

type Sender = {
  name: string;
  email: string;
  avatarUri?: string;
  avatarFallbackText?: string;
};

type StructuredContent = {
  contentType: 'structured';
  headline: string;
  subtitle: string;    // subject line — 12px gray, truncated
  body: string;        // summary — 16px
  cta?: { label: string; onPress: () => void };
  actionLabel?: string;
};

type HtmlContent = {
  contentType: 'html';
  source: string;
};

type Actions = {
  aiSuggestionCount?: number;
  onReact?: () => void;
  onReply?: () => void;
  onForward?: () => void;
  onAI?: () => void;
  onBookmark?: () => void;
  onDelete?: () => void;
};

type EmailCardProps = {
  sender: Sender;
  content: StructuredContent | HtmlContent;
  tag?: string;
  actions?: Actions;
  onOptionsPress?: () => void;
  timestamp?: string;          // e.g. "2 hours ago"
  threadMessageCount?: number; // e.g. 2
};

// ─── CardTag ──────────────────────────────────────────────────────────────

function CardTag({ text }: { text: string }) {
  return (
    <View style={styles.tag}>
      <Text style={styles.tagLabel}>{text}</Text>
    </View>
  );
}

// ─── Component ────────────────────────────────────────────────────────────

export default function EmailCard({
  sender,
  content,
  tag,
  actions = {},
  onOptionsPress,
  timestamp,
  threadMessageCount,
}: EmailCardProps) {
  const [imageError, setImageError] = useState(false);
  useEffect(() => { setImageError(false); }, [sender.avatarUri]);

  const {
    aiSuggestionCount,
    onReact,
    onReply,
    onForward,
    onAI,
    onBookmark,
    onDelete,
  } = actions;

  const threadLabel = threadMessageCount != null && threadMessageCount > 0
    ? `${threadMessageCount} email${threadMessageCount === 1 ? '' : 's'} in thread`
    : '';

  return (
    <View style={styles.card}>

      {/* ── Header ─────────────────────────────────────────────────── */}
      <View style={styles.header}>
        <View style={styles.headerLeft}>
          <View style={styles.avatarContainer}>
            {sender.avatarUri && !imageError ? (
              <Image
                source={{ uri: sender.avatarUri }}
                style={styles.avatar}
                onError={() => setImageError(true)}
              />
            ) : (
              <View style={styles.avatarFallback}>
                <Text style={styles.avatarInitial}>
                  {sender.avatarFallbackText ?? (sender.name || sender.email).charAt(0).toUpperCase()}
                </Text>
              </View>
            )}
          </View>
          <View style={styles.senderInfo}>
            <View style={styles.senderNameRow}>
              <Text style={styles.senderName} numberOfLines={1} ellipsizeMode="tail">
                {sender.name}
              </Text>
              {tag && <CardTag text={tag} />}
            </View>
            <Text style={styles.senderEmail} numberOfLines={1} ellipsizeMode="tail">
              {sender.email}
            </Text>
          </View>
        </View>
        <TouchableOpacity style={styles.optionsBtn} onPress={onOptionsPress} hitSlop={8}>
          <IconSymbol name="ellipsis" size={16} color={Colors.light.textPrimary} />
        </TouchableOpacity>
      </View>

      {/* ── Body ───────────────────────────────────────────────────── */}
      {content.contentType === 'structured' ? (
        <View style={styles.body}>
          <View style={styles.bodyTop}>
            <Text style={styles.headline}>{content.headline}</Text>
            <Text style={styles.subtitleGray} numberOfLines={1} ellipsizeMode="tail">
              {content.subtitle}
            </Text>
          </View>
          <Text style={styles.bodyText}>{content.body}</Text>
          {content.cta && (
            <TouchableOpacity
              style={styles.ctaBtn}
              onPress={content.cta.onPress}
              activeOpacity={0.7}
            >
              <Text style={styles.ctaLabel}>{content.cta.label}</Text>
            </TouchableOpacity>
          )}
          {!content.cta && content.actionLabel && (
            <Text style={styles.ctaLabel}>{content.actionLabel}</Text>
          )}
        </View>
      ) : (
        <View style={styles.body} />
      )}

      {/* ── Bottom ─────────────────────────────────────────────────── */}
      <View style={styles.bottom}>

        {/* Info bar */}
        <View style={styles.infoBar}>
          <View style={styles.infoItem}>
            <IconSymbol name="clock" size={16} color={Colors.light.textSecondary} />
            <Text style={styles.infoText}>{timestamp ?? ''}</Text>
          </View>
          <View style={styles.infoItem}>
            <IconSymbol name="bubble.left.and.bubble.right" size={16} color={Colors.light.textSecondary} />
            <Text style={styles.infoText}>{threadLabel}</Text>
          </View>
        </View>

        {/* Action Bar */}
        <View style={styles.actionBar}>
          <View style={styles.actions}>
            <TouchableOpacity style={styles.actionBtn} onPress={onReact} hitSlop={8}>
              <IconSymbol name="face.smiling" size={16} color={Colors.light.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.actionBtn} onPress={onReply} hitSlop={8}>
              <IconSymbol name="arrow.turn.up.left" size={16} color={Colors.light.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.actionBtn} onPress={onForward} hitSlop={8}>
              <IconSymbol name="arrow.turn.up.right" size={16} color={Colors.light.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.aiBtn} onPress={onAI} hitSlop={8}>
              <IconSymbol name="sparkles" size={16} color={Colors.light.textPrimary} />
              {aiSuggestionCount != null && (
                <Text style={styles.aiCount}>{aiSuggestionCount}</Text>
              )}
            </TouchableOpacity>
          </View>
          <View style={styles.actions}>
            <TouchableOpacity style={styles.actionBtn} onPress={onBookmark} hitSlop={8}>
              <IconSymbol name="bookmark" size={16} color={Colors.light.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.actionBtn} onPress={onDelete} hitSlop={8}>
              <IconSymbol name="trash" size={16} color={Colors.light.textPrimary} />
            </TouchableOpacity>
          </View>
        </View>

      </View>

    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  card: {
    backgroundColor: Colors.light.background,
    borderRadius: Radius.xl,
    borderWidth: 1,
    borderColor: Colors.light.border,
    padding: Spacing.lg,
    gap: Spacing.lg,
  },

  // Header
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    height: 42,
  },
  headerLeft: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    minWidth: 0,
  },
  avatarContainer: {
    width: Spacing.xl,
    height: Spacing.xl,
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
    fontSize: 12,
    color: Colors.light.textSecondary,
  },
  senderInfo: {
    flex: 1,
    flexDirection: 'column',
    gap: Spacing.xs,
    minWidth: 0,
  },
  senderNameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xs,
  },
  senderName: {
    fontFamily: InterFonts.regular,
    fontSize: 16,
    fontWeight: '400',
    color: Colors.light.textPrimary,
    letterSpacing: -0.32,
    flex: 1,
  },
  tag: {
    backgroundColor: Colors.light.surface,
    borderRadius: Radius.md,
    paddingHorizontal: Spacing.sm,
    paddingVertical: Spacing.xs,
    flexShrink: 0,
  },
  tagLabel: {
    fontFamily: InterFonts.medium,
    fontSize: 12,
    fontWeight: '500',
    color: Colors.light.textPrimary,
  },
  senderEmail: {
    fontFamily: InterFonts.regular,
    fontSize: 12,
    fontWeight: '400',
    color: Colors.light.textSecondary,
  },
  optionsBtn: {
    width: Spacing.xl,
    height: Spacing.xl,
    borderRadius: Radius.round,
    alignItems: 'center',
    justifyContent: 'flex-end',
    flexShrink: 0,
  },

  // Body
  body: {
    gap: Spacing.md,
  },
  bodyTop: {
    gap: 12,
  },
  headline: {
    ...Typography.displayLg,
    color: Colors.light.textPrimary,
  },
  subtitleGray: {
    fontFamily: InterFonts.medium,
    fontSize: 12,
    fontWeight: '500',
    color: Colors.light.textSecondary,
    lineHeight: 17,      // 12 × 1.4
    letterSpacing: -0.12,
  },
  bodyText: {
    fontFamily: InterFonts.regular,
    fontSize: 16,
    fontWeight: '400',
    color: Colors.light.textPrimary,
    lineHeight: 22,      // 16 × 1.4
    letterSpacing: -0.32,
  },
  ctaBtn: {
    borderWidth: 1,
    borderColor: Colors.light.textSecondary,
    borderRadius: Radius.xl,
    paddingHorizontal: Spacing.lg,
    paddingVertical: Spacing.md,
    alignSelf: 'flex-start',
  },
  ctaLabel: {
    fontFamily: InterFonts.regular,
    fontSize: 16,
    fontWeight: '400',
    color: Colors.light.textPrimary,
    letterSpacing: -0.32,
  },

  // Bottom
  bottom: {
    gap: 12,
  },
  infoBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  infoItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 2,
  },
  infoText: {
    fontFamily: InterFonts.medium,
    fontSize: 12,
    fontWeight: '500',
    color: Colors.light.textSecondary,
    lineHeight: 17,
    letterSpacing: -0.12,
  },

  // Action Bar
  actionBar: {
    borderTopWidth: 1,
    borderTopColor: Colors.light.border,
    paddingTop: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  actions: {
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
  aiBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xxs,
  },
  aiCount: {
    fontFamily: InterFonts.regular,
    fontSize: 12,
    color: Colors.light.textPrimary,
  },
});
