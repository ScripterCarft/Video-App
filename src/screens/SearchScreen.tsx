import { PlatformColor, StyleSheet, View } from 'react-native';

export function SearchScreen() {
  return <View style={styles.container} />;
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: PlatformColor('systemBackground'),
  },
});
