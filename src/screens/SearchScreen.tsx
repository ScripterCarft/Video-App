import { useEffect, useRef, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import type { SearchBarCommands } from 'react-native-screens';
import { dummyVideos } from '../data/dummyData';
import { VideoRow } from '../components/VideoRow';

export function SearchScreen() {
  const navigation = useNavigation();
  const [query, setQuery] = useState('');
  const searchBarRef = useRef<SearchBarCommands>(null);

  useEffect(() => {
    navigation.setOptions({
      headerSearchBarOptions: {
        ref: searchBarRef,
        placeholder: 'Videos, Kanäle',
        onChangeText: (event: { nativeEvent: { text: string } }) =>
          setQuery(event.nativeEvent.text),
      },
    });
  }, [navigation]);

  useEffect(() => {
    const parent = navigation.getParent();
    if (!parent) {
      return;
    }
    // getParent() returns the generic core navigation type, which doesn't
    // know about the tab navigator's 'tabPress' event.
    return (parent as any).addListener('tabPress', () => {
      if (navigation.isFocused()) {
        searchBarRef.current?.focus();
      }
    });
  }, [navigation]);

  const results = query.trim()
    ? dummyVideos.filter((video) =>
        video.title.toLowerCase().includes(query.trim().toLowerCase())
      )
    : [];

  return (
    <View style={styles.container}>
      {query.trim() && results.length === 0 ? (
        <View style={styles.empty}>
          <Text style={styles.emptyText}>Keine Ergebnisse für „{query}“</Text>
        </View>
      ) : (
        <FlatList
          style={styles.list}
          contentInsetAdjustmentBehavior="automatic"
          data={results}
          keyExtractor={(video) => video.id}
          renderItem={({ item }) => <VideoRow video={item} />}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: 'white',
  },
  list: {
    flex: 1,
  },
  empty: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 32,
  },
  emptyText: {
    color: '#8E8E93',
    fontSize: 15,
    textAlign: 'center',
  },
});
