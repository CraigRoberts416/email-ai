import { useEffect, useRef } from 'react';
import { Animated, StyleSheet, Text, View } from 'react-native';
import { Colors, InterFonts, Radius, Spacing } from '@/constants/theme';

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

// ─── Component ────────────────────────────────────────────────────────────

export default function UnsubscribeToast({ jobs }: Props) {
  const translateY = useRef(new Animated.Value(100)).current;
  const opacity    = useRef(new Animated.Value(0)).current;

  const activeJobs = jobs.filter(j => j.status !== 'done' && j.status !== 'error');
  const doneCount  = jobs.filter(j => j.status === 'done').length;
  const errorCount = jobs.filter(j => j.status === 'error').length;
  const total      = jobs.length;
  const visible    = jobs.length > 0;

  // Current job to narrate — first non-done, non-error one; else last done/error
  const current = activeJobs[0] ?? jobs[jobs.length - 1] ?? null;

  useEffect(() => {
    Animated.parallel([
      Animated.spring(translateY, {
        toValue: visible ? 0 : 100,
        useNativeDriver: true,
        damping: 20,
        stiffness: 200,
      }),
      Animated.timing(opacity, {
        toValue: visible ? 1 : 0,
        duration: 200,
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
    bottom: Spacing.lg,
    left: Spacing.md,
    right: Spacing.md,
    zIndex: 100,
  },
  toast: {
    backgroundColor: Colors.light.textPrimary,
    borderRadius: Radius.xl,
    paddingHorizontal: Spacing.md,
    paddingVertical: 14,
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.sm,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 8,
  },
  left: {
    flex: 1,
    gap: 2,
  },
  senderName: {
    fontFamily: InterFonts.medium,
    fontSize: 14,
    fontWeight: '500',
    color: Colors.light.background,
    letterSpacing: -0.2,
  },
  statusText: {
    fontFamily: InterFonts.regular,
    fontSize: 12,
    fontWeight: '400',
    color: '#AAAAAA',
  },
  badge: {
    backgroundColor: '#333333',
    borderRadius: Radius.round,
    paddingHorizontal: Spacing.sm,
    paddingVertical: Spacing.xs,
    flexShrink: 0,
  },
  badgeText: {
    fontFamily: InterFonts.medium,
    fontSize: 12,
    fontWeight: '500',
    color: Colors.light.background,
  },
});
