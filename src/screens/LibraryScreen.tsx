import { useRef, useState } from 'react';
import {
  FlatList,
  PlatformColor,
  StyleSheet,
  Switch,
  Text,
  View,
} from 'react-native';
import { useScrollToTop } from '@react-navigation/native';
import { dummyVideos } from '../data/dummyData';
import { VideoRow } from '../components/VideoRow';
import { useStrings } from '../i18n/strings';
import type { Video } from '../types/video';

export function LibraryScreen() {
  const strings = useStrings();
  const [commentsEnabled, setCommentsEnabled] = useState(true);
  const listRef = useRef<FlatList<Video>>(null);
  useScrollToTop(listRef);

  return (
    <FlatList
      ref={listRef}
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
    backgroundColor: PlatformColor('systemBackground'),
  },
  settingsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: PlatformColor('separator'),
  },
  settingsLabel: {
    color: PlatformColor('label'),
    fontSize: 15,
    fontWeight: '500',
  },
});
