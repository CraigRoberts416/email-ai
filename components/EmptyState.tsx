import { Pressable, StyleSheet, Text, View } from 'react-native';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { Radius, Spacing, Theme, Type } from '@/constants/theme';

type Props = {
  icon:      any;
  title:     string;
  detail:    string;
  cta?:      { label: string; onPress: () => void };
};

export default function EmptyState({ icon, title, detail, cta }: Props) {
  return (
    <View style={styles.container}>
      <View style={styles.iconWrap}>
        <IconSymbol name={icon} size={28} color={Theme.textSecondary} />
      </View>
      <Text style={styles.title}>{title}</Text>
      <Text style={styles.detail}>{detail}</Text>
      {cta && (
        <Pressable onPress={cta.onPress} style={styles.cta} accessibilityRole="button">
          <Text style={styles.ctaLabel}>{cta.label}</Text>
        </Pressable>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingVertical: Spacing['3xl'],
    paddingHorizontal: Spacing.xl,
    alignItems: 'center',
    gap: Spacing.md,
  },
  iconWrap: {
    width: 56, height: 56,
    borderRadius: 28,
    backgroundColor: Theme.surface,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: Spacing.sm,
  },
  title: {
    ...Type.headline,
    color: Theme.textPrimary,
    textAlign: 'center',
  },
  detail: {
    ...Type.body,
    color: Theme.textSecondary,
    textAlign: 'center',
    maxWidth: 300,
  },
  cta: {
    marginTop: Spacing.md,
    backgroundColor: Theme.accent,
    paddingHorizontal: Spacing.lg,
    paddingVertical: Spacing.md,
    borderRadius: Radius.control,
  },
  ctaLabel: {
    ...Type.sender,
    color: Theme.bg,
  },
});
