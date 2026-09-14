import { StyleSheet, Text, View } from 'react-native';
import { Radius, Spacing, Theme, Type } from '@/constants/theme';

// Status is an enum, never LLM-freeform. Feed rhythm depends on the pill
// being a stable, repeatable shape; language freedom belongs in the body.
export type StatusKind =
  | 'waiting-on-you'
  | 'waiting-on-them'
  | 'fyi'
  | 'promotion'
  | 'newsletter'
  | 'receipt'
  | 'calendar'
  | 'scam';

const LABEL: Record<StatusKind, string> = {
  'waiting-on-you':  'Waiting on you',
  'waiting-on-them': 'Waiting on them',
  'fyi':             'FYI',
  'promotion':       'Promotion',
  'newsletter':      'Newsletter',
  'receipt':         'Receipt',
  'calendar':        'Calendar',
  'scam':            'Possible scam',
};

// Pills borrow color from status semantics — but never accent coral, which
// is reserved for unread + one primary action per screen.
const COLOR: Record<StatusKind, string> = {
  'waiting-on-you':  Theme.textPrimary,
  'waiting-on-them': Theme.textSecondary,
  'fyi':             Theme.textSecondary,
  'promotion':       Theme.textSecondary,
  'newsletter':      Theme.textSecondary,
  'receipt':         Theme.textSecondary,
  'calendar':        Theme.textSecondary,
  'scam':            Theme.danger,
};

export default function StatusPill({ kind }: { kind: StatusKind }) {
  const color = COLOR[kind];
  const isScam = kind === 'scam';
  const isWaiting = kind === 'waiting-on-you';
  return (
    <View style={[
      styles.pill,
      isScam && styles.pillDanger,
      isWaiting && styles.pillEmphasis,
    ]}>
      <Text style={[styles.label, { color }]} numberOfLines={1}>
        {LABEL[kind]}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  pill: {
    paddingHorizontal: Spacing.sm,
    paddingVertical:   Spacing.xxs,
    borderRadius:      Radius.chip,
    backgroundColor:   Theme.surface,
    alignSelf:         'flex-start',
  },
  pillEmphasis: {
    backgroundColor: Theme.elevated,
  },
  pillDanger: {
    backgroundColor: 'rgba(255,78,91,0.12)',
  },
  label: {
    ...Type.chip,
  },
});
