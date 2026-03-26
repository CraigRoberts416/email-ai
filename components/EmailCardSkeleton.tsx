import { useEffect, useRef } from 'react';
import { Animated, StyleSheet, View } from 'react-native';
import { Colors, Radius, Spacing } from '@/constants/theme';

// Matches EmailCard container exactly (same border, radius, padding, gap)
// so the skeleton occupies the card's final footprint with no layout shift on resolve.

function Bar({ width, height = 14 }: { width: number | `${number}%`; height?: number }) {
  return <View style={[styles.bar, { width, height }]} />;
}

export default function EmailCardSkeleton() {
  const opacity = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    const anim = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, { toValue: 0.4, duration: 700, useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 1,   duration: 700, useNativeDriver: true }),
      ])
    );
    anim.start();
    return () => anim.stop();
  }, [opacity]);

  return (
    <Animated.View style={[styles.card, { opacity }]}>

      {/* Header — mirrors EmailCard header height (42px) */}
      <View style={styles.header}>
        <View style={styles.avatarPlaceholder} />
        <View style={styles.senderInfo}>
          <Bar width="52%" height={14} />
          <Bar width="36%" height={10} />
        </View>
      </View>

      {/* Body — mirrors headline + body text area */}
      <View style={styles.body}>
        <Bar width="88%" height={24} />
        <Bar width="65%" height={24} />
        <Bar width="95%" height={14} />
        <Bar width="78%" height={14} />
      </View>

      {/* Bottom — mirrors info bar + action bar */}
      <View style={styles.bottom}>
        <View style={styles.infoBar}>
          <Bar width={72} height={12} />
          <Bar width={96} height={12} />
        </View>
        <View style={styles.divider} />
        <View style={styles.actionRow}>
          {[0, 1, 2, 3].map(i => (
            <View key={i} style={styles.actionDot} />
          ))}
        </View>
      </View>

    </Animated.View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: Colors.light.background,
    borderRadius: Radius.xl,
    borderWidth: 1,
    borderColor: Colors.light.border,
    padding: Spacing.lg,
    gap: Spacing.lg,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 42,
    gap: Spacing.sm,
  },
  avatarPlaceholder: {
    width: Spacing.xl,
    height: Spacing.xl,
    borderRadius: Radius.round,
    backgroundColor: Colors.light.surface,
    flexShrink: 0,
  },
  senderInfo: {
    flex: 1,
    gap: Spacing.xs,
  },
  body: {
    gap: Spacing.sm,
  },
  bottom: {
    gap: 12,
  },
  infoBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  divider: {
    height: 1,
    backgroundColor: Colors.light.border,
  },
  actionRow: {
    flexDirection: 'row',
    gap: Spacing.md,
  },
  actionDot: {
    width: Spacing.lg,
    height: Spacing.lg,
    borderRadius: Radius.round,
    backgroundColor: Colors.light.surface,
  },
  bar: {
    backgroundColor: Colors.light.surface,
    borderRadius: Radius.md,
  },
});
