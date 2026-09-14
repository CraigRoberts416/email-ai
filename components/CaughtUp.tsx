import { StyleSheet, Text, View } from 'react-native';
import Animated, { FadeIn } from 'react-native-reanimated';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { Spacing, Theme, Type } from '@/constants/theme';

type Props = {
  // The AI-generated resolution line, if we have one.
  // Falls back to a static line if the LLM copy hasn't arrived — this is
  // the app's "return to your life" moment, and it MUST be present.
  line?: string | null;
  // What was cleared, e.g. "12 things, none left waiting on you"
  detail?: string | null;
};

export default function CaughtUp({ line, detail }: Props) {
  return (
    <Animated.View
      style={styles.container}
      entering={FadeIn.duration(300)}
    >
      <View style={styles.mark}>
        <IconSymbol name="checkmark" size={22} color={Theme.success} />
      </View>
      <Text style={styles.headline}>
        {line ?? "You're caught up."}
      </Text>
      {detail ? (
        <Text style={styles.detail}>{detail}</Text>
      ) : null}
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingVertical: Spacing['3xl'],
    paddingHorizontal: Spacing.xl,
    alignItems: 'center',
    gap: Spacing.md,
  },
  mark: {
    width: 44, height: 44,
    borderRadius: 22,
    borderWidth: 1,
    borderColor: Theme.success,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: Spacing.xs,
  },
  headline: {
    ...Type.headline,
    color: Theme.textPrimary,
    textAlign: 'center',
  },
  detail: {
    ...Type.body,
    color: Theme.textSecondary,
    textAlign: 'center',
    maxWidth: 280,
  },
});
