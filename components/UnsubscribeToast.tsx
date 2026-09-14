import { useEffect, useRef } from 'react';
import { Animated, StyleSheet, Text, View } from 'react-native';
import { Radius, Spacing, Theme, Type } from '@/constants/theme';

// ─── Types ────────────────────────────────────────────────────────────────

export type UnsubscribeJob = {
  messageId: string;
  senderName: string;
  status: 'queued' | 'navigating' | 'analyzing' | 'filling' | 'clicking' | 'verifying' | 'done' | 'error';
  message: string;
};

type Props = {
  jobs: UnsubscribeJob[];
};

function statusColor(status: UnsubscribeJob['status']): string {
  if (status === 'done')  return Theme.success;
  if (status === 'error') return Theme.danger;
  return Theme.warning;
}

// ─── Component ────────────────────────────────────────────────────────────

export default function UnsubscribeToast({ jobs }: Props) {
  const translateY = useRef(new Animated.Value(120)).current;
  const opacity    = useRef(new Animated.Value(0)).current;

  const activeJobs = jobs.filter(j => j.status !== 'done' && j.status !== 'error');
  const doneCount  = jobs.filter(j => j.status === 'done').length;
  const errorCount = jobs.filter(j => j.status === 'error').length;
  const total      = jobs.length;
  const visible    = jobs.length > 0;

  // Narrate the first in-flight job; fall back to the last resolved one.
  const current = activeJobs[0] ?? jobs[jobs.length - 1] ?? null;

  useEffect(() => {
    Animated.parallel([
      Animated.spring(translateY, {
        toValue: visible ? 0 : 120,
        useNativeDriver: true,
        damping: 22,
        stiffness: 260,
      }),
      Animated.timing(opacity, {
        toValue: visible ? 1 : 0,
        duration: 180,
        useNativeDriver: true,
      }),
    ]).start();
  }, [visible, translateY, opacity]);

  if (!current) return null;

  const completedCount = doneCount + errorCount;
  const showProgress   = total > 1;

  return (
    <Animated.View style={[styles.container, { transform: [{ translateY }], opacity }]}>
      <View style={styles.toast}>
        <View style={[styles.dot, { backgroundColor: statusColor(current.status) }]} />
        <View style={styles.left}>
          <Text style={styles.senderName} numberOfLines={1}>
            {current.senderName}
          </Text>
          <Text style={styles.statusText} numberOfLines={2}>
            {current.message}
          </Text>
        </View>
        {showProgress && (
          <View style={styles.badge}>
            <Text style={styles.badgeText}>{completedCount}/{total}</Text>
          </View>
        )}
      </View>
    </Animated.View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    bottom: Spacing.xl,
    left: Spacing.md,
    right: Spacing.md,
    zIndex: 100,
  },
  toast: {
    backgroundColor: Theme.elevated,
    borderRadius: Radius.sheet,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Theme.border,
    paddingHorizontal: Spacing.lg,
    paddingVertical: Spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.md,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.4,
    shadowRadius: 16,
    elevation: 10,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    flexShrink: 0,
  },
  left: {
    flex: 1,
    gap: 2,
  },
  senderName: {
    ...Type.sender,
    color: Theme.textPrimary,
  },
  statusText: {
    ...Type.caption,
    color: Theme.textSecondary,
  },
  badge: {
    backgroundColor: Theme.surface,
    borderRadius: Radius.round,
    paddingHorizontal: Spacing.sm,
    paddingVertical: Spacing.xs,
    flexShrink: 0,
  },
  badgeText: {
    ...Type.metaBold,
    color: Theme.textSecondary,
  },
});
