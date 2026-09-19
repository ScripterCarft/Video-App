import { useRef } from 'react';
import { FlatList, PlatformColor, StyleSheet } from 'react-native';
import { useScrollToTop } from '@react-navigation/native';
import { dummyVideos } from '../data/dummyData';
import { VideoRow } from '../components/VideoRow';
import type { Video } from '../types/video';

export function HomeScreen() {
  const listRef = useRef<FlatList<Video>>(null);
  useScrollToTop(listRef);

  return (
    <FlatList
      ref={listRef}
      style={styles.list}
      contentInsetAdjustmentBehavior="automatic"
      data={dummyVideos}
      keyExtractor={(video) => video.id}
      renderItem={({ item }) => <VideoRow video={item} />}
    />
  );
}

const styles = StyleSheet.create({
  list: {
    flex: 1,
    backgroundColor: PlatformColor('systemBackground'),
  },
});
