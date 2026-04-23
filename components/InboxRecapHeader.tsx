import { Colors, Spacing, Typography } from '@/constants/theme';
import { StyleSheet, Text, View } from 'react-native';

type RecapData = {
  greeting: string;
  summary: string;
  totalInView: number;
  requireAttention: number;
};

type Props = {
  recap: RecapData;
  inViewLabel?: string;
  needAttentionLabel?: string;
};

export default function InboxRecapHeader({ recap, inViewLabel = 'in view', needAttentionLabel = 'need attention' }: Props) {
  return (
    <View style={styles.container}>
      <Text style={styles.greeting}>{recap.greeting}</Text>
      <Text style={styles.summary}>{recap.summary}</Text>
      <View style={styles.metaRow}>
        <Text style={styles.metaItem}>{recap.totalInView} {inViewLabel}</Text>
        <Text style={styles.metaItem}>{recap.requireAttention} {needAttentionLabel}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingTop: Spacing.xl,
    paddingBottom: Spacing.lg,
    gap: Spacing.md,
  },
  greeting: {
    ...Typography.displayLg,
    color: Colors.light.textPrimary,
  },
  summary: {
    ...Typography.bodyMd,
    color: Colors.light.textSecondary,
  },
  metaRow: {
    flexDirection: 'row',
    gap: 18,
    alignItems: 'center',
  },
  metaItem: {
    ...Typography.bodyMd,
    color: Colors.light.textSecondary,
  },
});
