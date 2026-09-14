import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import Animated, {
  Extrapolation,
  interpolate,
  SharedValue,
  useAnimatedStyle,
  withSpring,
} from 'react-native-reanimated';
import * as Haptics from 'expo-haptics';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { Layout as L, Motion, Radius, Spacing, Theme, Type } from '@/constants/theme';

export type FeedMode = 'feed' | 'all-mail';

type Props = {
  scrollY:      SharedValue<number>;
  mode:         FeedMode;
  onModeChange: (m: FeedMode) => void;
  unreadLabel?: string;    // e.g. "5 waiting"
  onSettings?:  () => void;
};

export default function FeedHeader({ scrollY, mode, onModeChange, unreadLabel, onSettings }: Props) {
  // Scroll-driven collapse. Everything on the worklet — no JS-thread timing.
  const collapse = useAnimatedStyle(() => {
    const t = interpolate(
      scrollY.value,
      [0, 80],
      [0, 1],
      Extrapolation.CLAMP
    );
    return {
      height:  interpolate(t, [0, 1], [L.headerExpandedHeight, L.headerCollapsedHeight]),
      opacity: interpolate(t, [0, 1], [1, 0.98]),
    };
  });

  const titleAnim = useAnimatedStyle(() => {
    const t = interpolate(scrollY.value, [0, 80], [0, 1], Extrapolation.CLAMP);
    return {
      transform: [
        { translateY: interpolate(t, [0, 1], [0, -8]) },
        { scale:      interpolate(t, [0, 1], [1, 0.9]) },
      ],
      opacity: interpolate(t, [0, 1], [1, 0]),
    };
  });

  const compactTitleAnim = useAnimatedStyle(() => {
    const t = interpolate(scrollY.value, [40, 90], [0, 1], Extrapolation.CLAMP);
    return {
      opacity: t,
      transform: [{ translateY: interpolate(t, [0, 1], [4, 0]) }],
    };
  });

  return (
    <Animated.View style={[styles.container, collapse]}>
      {/* Compact centered title, appears as expanded fades out */}
      <Animated.View style={[styles.compact, compactTitleAnim]} pointerEvents="none">
        <Text style={styles.compactTitle}>
          {mode === 'feed' ? 'Inbox' : 'All mail'}
        </Text>
      </Animated.View>

      {/* Expanded content */}
      <Animated.View style={[styles.expanded, titleAnim]}>
        <View style={styles.topLine}>
          <Text style={styles.brand}>Decision Inbox</Text>
          {onSettings && (
            <Pressable
              onPress={() => { Haptics.selectionAsync().catch(() => {}); onSettings(); }}
              hitSlop={12}
              accessibilityRole="button"
              accessibilityLabel="Settings"
              style={styles.iconBtn}
            >
              <IconSymbol name="gearshape" size={20} color={Theme.textSecondary} />
            </Pressable>
          )}
        </View>
        {unreadLabel ? (
          <Text style={styles.unreadLabel}>{unreadLabel}</Text>
        ) : null}
      </Animated.View>

      {/* Mode toggle — always visible */}
      <ModeToggle mode={mode} onChange={onModeChange} />
    </Animated.View>
  );
}

// ─── ModeToggle ───────────────────────────────────────────────────────────

function ModeToggle({ mode, onChange }: { mode: FeedMode; onChange: (m: FeedMode) => void }) {
  const feed = mode === 'feed';
  // Measure the track so the indicator can spring between halves instead of
  // snapping via a `left` swap.
  const [trackWidth, setTrackWidth] = useState(0);
  const half = Math.max(0, (trackWidth - 8) / 2);

  const indicator = useAnimatedStyle(() => ({
    width: half,
    transform: [{ translateX: withSpring(feed ? 0 : half, Motion.spring.tab) }],
  }));

  return (
    <View
      style={styles.toggle}
      onLayout={e => setTrackWidth(e.nativeEvent.layout.width)}
    >
      <Animated.View style={[styles.toggleIndicator, indicator]} />
      <Pressable
        onPress={() => { if (!feed) { Haptics.selectionAsync().catch(() => {}); onChange('feed'); } }}
        style={styles.toggleBtn}
        accessibilityRole="tab"
        accessibilityState={{ selected: feed }}
      >
        <Text style={[styles.toggleLabel, feed && styles.toggleLabelActive]}>Feed</Text>
      </Pressable>
      <Pressable
        onPress={() => { if (feed) { Haptics.selectionAsync().catch(() => {}); onChange('all-mail'); } }}
        style={styles.toggleBtn}
        accessibilityRole="tab"
        accessibilityState={{ selected: !feed }}
      >
        <Text style={[styles.toggleLabel, !feed && styles.toggleLabelActive]}>All mail</Text>
      </Pressable>
    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  container: {
    backgroundColor: Theme.bg,
    paddingHorizontal: Spacing.lg,
    justifyContent: 'flex-end',
    paddingBottom: Spacing.sm,
    overflow: 'hidden',
  },
  expanded: {
    gap: Spacing.xs,
  },
  topLine: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  brand: {
    ...Type.display,
    fontSize: 28,
    lineHeight: 32,
    color: Theme.textPrimary,
  },
  unreadLabel: {
    ...Type.body,
    color: Theme.textSecondary,
  },
  compact: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    alignItems: 'center',
    justifyContent: 'flex-end',
    paddingBottom: 56, // sits above toggle
  },
  compactTitle: {
    ...Type.sender,
    color: Theme.textPrimary,
    fontSize: 16,
  },
  iconBtn: {
    width: 36, height: 36,
    borderRadius: Radius.round,
    alignItems: 'center',
    justifyContent: 'center',
  },
  toggle: {
    marginTop: Spacing.md,
    flexDirection: 'row',
    backgroundColor: Theme.surface,
    borderRadius: Radius.control,
    padding: 4,
    position: 'relative',
  },
  toggleIndicator: {
    position: 'absolute',
    top: 4, bottom: 4, left: 4,
    backgroundColor: Theme.elevated,
    borderRadius: Radius.control,
  },
  toggleBtn: {
    flex: 1,
    paddingVertical: 8,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 1,
  },
  toggleLabel: {
    ...Type.sender,
    color: Theme.textSecondary,
  },
  toggleLabelActive: {
    color: Theme.textPrimary,
  },
});
