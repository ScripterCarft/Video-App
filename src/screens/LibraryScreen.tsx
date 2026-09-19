import { useState } from 'react';
import { FlatList, StyleSheet, Switch, Text, View } from 'react-native';
import { dummyVideos } from '../data/dummyData';
import { VideoRow } from '../components/VideoRow';
import { useStrings } from '../i18n/strings';

export function LibraryScreen() {
  const strings = useStrings();
  const [commentsEnabled, setCommentsEnabled] = useState(true);

  return (
    <FlatList
      style={styles.list}
      contentInsetAdjustmentBehavior="automatic"
      data={dummyVideos}
      keyExtractor={(video) => video.id}
      ListHeaderComponent={
        <View style={styles.settingsRow}>
          <Text style={styles.settingsLabel}>{strings.library.showComments}</Text>
          <Switch value={commentsEnabled} onValueChange={setCommentsEnabled} />
        </View>
      }
      renderItem={({ item }) => <VideoRow video={item} />}
    />
  );
}

const styles = StyleSheet.create({
  list: {
    flex: 1,
    backgroundColor: 'white',
  },
  settingsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#D1D1D6',
  },
  settingsLabel: {
    fontSize: 15,
    fontWeight: '500',
  },
});
