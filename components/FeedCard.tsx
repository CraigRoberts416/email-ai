import React, { useEffect, useState } from 'react';
import {
  AccessibilityInfo,
  Dimensions,
  Image,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import Animated, {
  Easing,
  FadeIn,
  LinearTransition,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withSequence,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import * as Haptics from 'expo-haptics';
import { IconSymbol } from '@/components/ui/icon-symbol';
import StatusPill, { StatusKind } from '@/components/StatusPill';
import { Layout as L, Motion, Radius, Spacing, Theme, Type } from '@/constants/theme';

const SCREEN_W = Dimensions.get('window').width;

// ─── Types ────────────────────────────────────────────────────────────────

export type FeedCardSender = {
  name:                string;
  email:               string;
  avatarUri?:          string | null;
  avatarFallbackText?: string;
};

export type FeedCardKind = 'standard' | 'marketing';

export type FeedCardProps = {
  sender:      FeedCardSender;
  kind:        FeedCardKind;
  status:      StatusKind;
  headline:    string | null;      // AI quote — null while streaming
  body:        string | null;      // AI summary — null while streaming
  timestamp:   string;             // relative, e.g. "2h"
  unread:      boolean;
  threadCount?: number;            // renders "+3" inline with the sender
  loading?:    boolean;            // AI still streaming
  /**
   * True only for cards that genuinely just arrived (SSE push). FlatList
   * remounts recycled rows during scroll, and an unconditional `entering`
   * makes every row re-animate — the classic RN tell.
   */
  isNew?:      boolean;
  onOpen?:     () => void;
  onReply?:    () => void;
  onDiscuss?:  () => void;
  onForward?:  () => void;
  onSave?:     () => void;
  onArchive?:  () => void;
  onUnsubscribe?: () => void;
  onOverflow?: () => void;
};

// ─── FeedCard ─────────────────────────────────────────────────────────────

function FeedCardInner(props: FeedCardProps) {
  const {
    sender, kind, status, headline, body, timestamp,
    unread, threadCount, loading, isNew, onOpen, onReply, onDiscuss,
    onForward, onSave, onArchive, onUnsubscribe, onOverflow,
  } = props;

  const [reduceMotion, setReduceMotion] = useState(false);
  useEffect(() => {
    AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion);
    const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => sub?.remove?.();
  }, []);

  const isMarketing = kind === 'marketing';
  const canSwipeRight = isMarketing && !!onUnsubscribe;

  // ── Gesture + press state ─────────────────────────────────────────────
  const translateX = useSharedValue(0);
  const scale      = useSharedValue(1);
  const armed      = useSharedValue(false);

  const commitThreshold = SCREEN_W * Motion.swipe.commitFraction;
  // Reduced motion users get a shorter throw so the gesture stays reachable.
  const threshold = reduceMotion ? SCREEN_W * 0.3 : commitThreshold;

  const fireArmHaptic = () => { Haptics.selectionAsync().catch(() => {}); };
  const fireArchive   = () => { onArchive?.(); };
  const fireUnsub     = () => { onUnsubscribe?.(); };

  const swipe = Gesture.Pan()
    .activeOffsetX([-12, 12])
    .failOffsetY([-16, 16])
    .onUpdate((e) => {
      let x = e.translationX;
      // Only allow right-swipe when there's an unsubscribe action behind it.
      if (x > 0 && !canSwipeRight) x = 0;
      // Rubber-band past 60% so the card never feels like it left the rails.
      const limit = SCREEN_W * Motion.swipe.rubberBandAt;
      if (Math.abs(x) > limit) {
        const overshoot = Math.abs(x) - limit;
        x = Math.sign(x) * (limit + overshoot * 0.25);
      }
      translateX.value = x;

      const nowArmed = Math.abs(x) > threshold;
      if (nowArmed !== armed.value) {
        armed.value = nowArmed;
        if (nowArmed) runOnJS(fireArmHaptic)();
      }
    })
    .onEnd((e) => {
      const past = Math.abs(translateX.value) > threshold;
      const fast = Math.abs(e.velocityX) > Motion.swipe.commitVelocity;
      const goingLeft = translateX.value < 0;

      if (past || fast) {
        const target = goingLeft ? -SCREEN_W : SCREEN_W;
        translateX.value = withTiming(target, {
          duration: Motion.timing.exitSwipe,
          easing: Easing.bezier(0.32, 0, 0.67, 0),
        });
        runOnJS(goingLeft ? fireArchive : fireUnsub)();
      } else {
        translateX.value = withSpring(0, Motion.spring.cardEnter);
      }
      armed.value = false;
    });

  const cardAnim = useAnimatedStyle(() => ({
    transform: [
      { translateX: translateX.value },
      { scale: scale.value },
    ],
  }));

  // Action rail revealed behind the card as it slides.
  const railAnim = useAnimatedStyle(() => {
    const progress = Math.min(1, Math.abs(translateX.value) / threshold);
    return { opacity: progress };
  });

  const pressIn  = () => { scale.value = withTiming(0.985, { duration: Motion.timing.pressIn,  easing: Easing.out(Easing.quad) }); };
  const pressOut = () => { scale.value = withTiming(1,     { duration: Motion.timing.pressOut, easing: Easing.out(Easing.quad) }); };

  const senderStyle = unread ? Type.sender : Type.senderRead;
  const senderColor = unread ? Theme.textPrimary : Theme.textSecondary;

  const entering = !isNew
    ? undefined
    : reduceMotion
      ? FadeIn.duration(160)
      : FadeIn.duration(Motion.timing.reveal).easing(Easing.out(Easing.cubic));

  return (
    <Animated.View
      // Neighbors close the gap when a card leaves — runs in parallel with
      // the exit, never sequenced after it.
      layout={reduceMotion ? undefined : LinearTransition.springify().damping(22).stiffness(260)}
      entering={entering}
    >
      {/* Swipe rail sits behind the card and fades in with travel */}
      <Animated.View style={[styles.rail, railAnim]} pointerEvents="none">
        <View style={styles.railRight}>
          <IconSymbol name="xmark" size={18} color={Theme.warning} />
          <Text style={[styles.railLabel, { color: Theme.warning }]}>Unsubscribe</Text>
        </View>
        <View style={styles.railLeft}>
          <Text style={[styles.railLabel, { color: Theme.textSecondary }]}>Archive</Text>
          <IconSymbol name="archivebox" size={18} color={Theme.textSecondary} />
        </View>
      </Animated.View>

      <GestureDetector gesture={swipe}>
        <Animated.View style={cardAnim}>
          <Pressable
            onPress={onOpen}
            onPressIn={pressIn}
            onPressOut={pressOut}
            android_disableSound
            style={({ pressed }) => [styles.card, pressed && styles.cardPressed]}
          >
            {/* ── Top row: status + meta rail ──────────────────────── */}
            <View style={styles.topRow}>
              <StatusPill kind={status} />
              <View style={styles.topRight}>
                {unread && <View style={styles.unreadDot} />}
                <Text style={styles.timestamp}>{timestamp}</Text>
                <Pressable
                  onPress={onOverflow}
                  hitSlop={12}
                  accessibilityRole="button"
                  accessibilityLabel="More actions"
                  style={styles.overflowBtn}
                >
                  <IconSymbol name="ellipsis" size={18} color={Theme.textSecondary} />
                </Pressable>
              </View>
            </View>

            {/* ── Sender ───────────────────────────────────────────── */}
            <View style={styles.header}>
              <Avatar sender={sender} kind={kind} />
              <View style={styles.senderCol}>
                <View style={styles.senderRow}>
                  <Text
                    style={[senderStyle, { color: senderColor }]}
                    numberOfLines={1}
                    ellipsizeMode="tail"
                  >
                    {sender.name || sender.email}
                  </Text>
                  {threadCount != null && threadCount > 0 && (
                    <Text style={styles.threadCount}>+{threadCount}</Text>
                  )}
                </View>
              </View>
            </View>

            {/* ── Body ─────────────────────────────────────────────── */}
            {!isMarketing ? (
              <View style={styles.body}>
                {headline !== null ? (
                  <Text style={styles.headline}>{headline}</Text>
                ) : loading ? (
                  <StreamingCaret label="Reading this one…" />
                ) : null}

                {body !== null ? (
                  <Text style={styles.bodyText} numberOfLines={3} ellipsizeMode="tail">
                    {body}
                  </Text>
                ) : null}
              </View>
            ) : (
              <View style={styles.marketingBody}>
                {headline ?? body ? (
                  <Text style={styles.marketingLine} numberOfLines={2} ellipsizeMode="tail">
                    {headline ?? body}
                  </Text>
                ) : loading ? (
                  <StreamingCaret label="Reading this one…" />
                ) : null}
              </View>
            )}

            {/* ── Action row ───────────────────────────────────────── */}
            <View style={styles.actions}>
              {isMarketing ? (
                <>
                  <PrimaryAction icon="xmark" label="Unsubscribe" onPress={onUnsubscribe} />
                  <ActionButton icon="sparkles" label="Discuss" onPress={onDiscuss} />
                  <View style={styles.spacer} />
                  <ActionButton icon="bookmark"   label="Save"    onPress={onSave} />
                  <ActionButton icon="archivebox" label="Archive" onPress={onArchive} />
                </>
              ) : (
                <>
                  <ActionButton icon="arrowshape.turn.up.left"  label="Reply"   onPress={onReply} />
                  <ActionButton icon="sparkles"                 label="Discuss" onPress={onDiscuss} />
                  <ActionButton icon="arrowshape.turn.up.right" label="Forward" onPress={onForward} />
                  <View style={styles.spacer} />
                  <ActionButton icon="bookmark"   label="Save"    onPress={onSave} />
                  <ActionButton icon="archivebox" label="Archive" onPress={onArchive} />
                </>
              )}
            </View>
          </Pressable>
        </Animated.View>
      </GestureDetector>
    </Animated.View>
  );
}

export default React.memo(FeedCardInner);

// ─── Avatar ───────────────────────────────────────────────────────────────

function Avatar({ sender, kind }: { sender: FeedCardSender; kind: FeedCardKind }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [sender.avatarUri]);

  const fallback = sender.avatarFallbackText
    || (sender.name || sender.email || '?').charAt(0).toUpperCase();
  const isBrand = kind === 'marketing';

  if (sender.avatarUri && !failed) {
    return (
      <Image
        source={{ uri: sender.avatarUri }}
        onError={() => setFailed(true)}
        style={[styles.avatar, isBrand && styles.avatarBrand]}
      />
    );
  }
  return (
    <View style={[styles.avatar, isBrand && styles.avatarBrand, styles.avatarFallback]}>
      <Text style={styles.avatarInitial}>{fallback}</Text>
    </View>
  );
}

// ─── Action buttons ───────────────────────────────────────────────────────

function ActionButton({ icon, label, onPress }: { icon: any; label: string; onPress?: () => void }) {
  const scale = useSharedValue(1);
  const style = useAnimatedStyle(() => ({ transform: [{ scale: scale.value }] }));
  return (
    <Pressable
      onPress={() => {
        if (!onPress) return;
        Haptics.selectionAsync().catch(() => {});
        onPress();
      }}
      onPressIn={() => { scale.value = withTiming(0.9, { duration: 90, easing: Easing.out(Easing.quad) }); }}
      onPressOut={() => {
        scale.value = withSequence(
          withTiming(1.03, { duration: 90 }),
          withTiming(1,    { duration: 120 })
        );
      }}
      hitSlop={10}
      accessibilityRole="button"
      accessibilityLabel={label}
      style={styles.actionBtn}
    >
      <Animated.View style={style}>
        <IconSymbol name={icon} size={L.actionIconSize} color={Theme.textSecondary} />
      </Animated.View>
    </Pressable>
  );
}

function PrimaryAction({ icon, label, onPress }: { icon: any; label: string; onPress?: () => void }) {
  const scale = useSharedValue(1);
  const style = useAnimatedStyle(() => ({ transform: [{ scale: scale.value }] }));
  return (
    <Pressable
      onPress={() => {
        if (!onPress) return;
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(() => {});
        onPress();
      }}
      onPressIn={() => { scale.value = withTiming(0.96, { duration: 90, easing: Easing.out(Easing.quad) }); }}
      onPressOut={() => { scale.value = withTiming(1, { duration: 120 }); }}
      accessibilityRole="button"
      accessibilityLabel={label}
    >
      <Animated.View style={[styles.primaryBtn, style]}>
        <IconSymbol name={icon} size={14} color={Theme.accent} />
        <Text style={styles.primaryLabel}>{label}</Text>
      </Animated.View>
    </Pressable>
  );
}

// ─── Streaming caret ──────────────────────────────────────────────────────
// Generation is the substance of the product, so the wait state shows the
// model working rather than a skeleton pretending to be content.

function StreamingCaret({ label }: { label: string }) {
  const opacity = useSharedValue(0.4);
  useEffect(() => {
    const pulse = () => {
      opacity.value = withSequence(
        withTiming(1,   { duration: 500 }),
        withTiming(0.4, { duration: 500 })
      );
    };
    pulse();
    const id = setInterval(pulse, 1000);
    return () => clearInterval(id);
  }, [opacity]);
  const style = useAnimatedStyle(() => ({ opacity: opacity.value }));
  return (
    <View style={styles.caretRow}>
      <Animated.View style={[styles.caret, style]} />
      <Text style={styles.caretLabel}>{label}</Text>
    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  // Cards float on bg — no border, no shadow, no radius. Separation is the
  // 24pt of bg baked into paddingBottom.
  card: {
    backgroundColor:   Theme.bg,
    paddingTop:        L.cardTopPad,
    paddingBottom:     L.cardBottomPad,
    paddingHorizontal: L.cardGutter,
    gap:               Spacing.md,
  },
  cardPressed: {
    backgroundColor: '#111116',   // 4% white over bg, no hue shift
  },

  // Swipe rail
  rail: {
    ...StyleSheet.absoluteFillObject,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Spacing.lg,
  },
  railLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  railRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  railLabel: {
    ...Type.chip,
  },

  // Top row
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  topRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
  },
  unreadDot: {
    width:  L.unreadDotSize,
    height: L.unreadDotSize,
    borderRadius: L.unreadDotSize / 2,
    backgroundColor: Theme.accent,
  },
  timestamp: {
    ...Type.meta,
    color: Theme.textSecondary,
  },
  overflowBtn: {
    padding: 2,
  },

  // Sender
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
  },
  avatar: {
    width:  L.avatarSize,
    height: L.avatarSize,
    borderRadius: L.avatarSize / 2,
    backgroundColor: Theme.surface,
  },
  avatarBrand: {
    borderRadius: Radius.control,
  },
  avatarFallback: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarInitial: {
    ...Type.sender,
    color: Theme.textSecondary,
  },
  senderCol: {
    flex: 1,
    minWidth: 0,
  },
  senderRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: Spacing.sm,
  },
  threadCount: {
    ...Type.metaBold,
    color: Theme.textTertiary,
  },

  // Body
  body: {
    gap: Spacing.xs,
  },
  headline: {
    ...Type.headline,
    color: Theme.textPrimary,
  },
  bodyText: {
    ...Type.body,
    color: Theme.textSecondary,
  },
  caretRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    paddingVertical: Spacing.xs,
  },
  caret: {
    width:  9,
    height: 22,
    borderRadius: 2,
    backgroundColor: Theme.accent,
  },
  caretLabel: {
    ...Type.body,
    color: Theme.textTertiary,
  },

  // Marketing
  marketingBody: {
    paddingVertical: Spacing.xxs,
  },
  marketingLine: {
    ...Type.body,
    color: Theme.textPrimary,
  },

  // Actions
  actions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
    marginTop: Spacing.xxs,
  },
  spacer: {
    flex: 1,
  },
  actionBtn: {
    width:  L.actionIconSize + 10,
    height: L.actionIconSize + 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  // Outlined rather than coral-filled: a scrolling feed can show many
  // marketing cards at once, and filled accents on each would swamp the
  // unread dot, which is the accent's real job.
  primaryBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.xs,
    borderWidth: 1,
    borderColor: Theme.accent,
    paddingHorizontal: Spacing.md,
    paddingVertical: 6,
    borderRadius: Radius.control,
  },
  primaryLabel: {
    ...Type.sender,
    fontSize: 14,
    color: Theme.accent,
  },
});
