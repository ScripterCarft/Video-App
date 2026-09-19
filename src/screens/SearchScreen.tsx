import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { FlatList, PlatformColor, StyleSheet, Text, View } from 'react-native';
import { useNavigation, useScrollToTop } from '@react-navigation/native';
import type { BottomTabNavigationProp } from '@react-navigation/bottom-tabs';
import type { SearchBarCommands } from 'react-native-screens';
import { dummyVideos } from '../data/dummyData';
import { VideoRow } from '../components/VideoRow';
import { useStrings } from '../i18n/strings';
import type { Video } from '../types/video';
import type { RootTabParamList } from '../navigation/RootTabs';

export function SearchScreen() {
  const navigation = useNavigation();
  const strings = useStrings();
  const [query, setQuery] = useState('');
  const listRef = useRef<FlatList<Video>>(null);
  const searchBarRef = useRef<SearchBarCommands>(null);
  useScrollToTop(listRef);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerSearchBarOptions: {
        ref: searchBarRef,
        placeholder: strings.search.placeholder,
        hideWhenScrolling: false,
        onChange: (event: { nativeEvent: { text: string } }) =>
          setQuery(event.nativeEvent.text),
        onCancelButtonPress: () => setQuery(''),
      },
    });
  }, [navigation, strings]);

  useEffect(() => {
    const tabNavigation = navigation.getParent() as
      | BottomTabNavigationProp<RootTabParamList>
      | undefined;

    return tabNavigation?.addListener('tabPress', (event) => {
      const searchRoute = tabNavigation
        .getState()
        .routes.find((route) => route.name === 'SearchTab');

      if (navigation.isFocused() && event.target === searchRoute?.key) {
        requestAnimationFrame(() => searchBarRef.current?.focus());
      }
    });
  }, [navigation]);

  const normalizedQuery = query.trim();
  const results = normalizedQuery
    ? dummyVideos.filter((video) =>
        video.title.toLowerCase().includes(normalizedQuery.toLowerCase())
      )
    : [];

  return (
    <FlatList
      ref={listRef}
      style={styles.list}
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={
        normalizedQuery && results.length === 0 ? styles.emptyContent : undefined
      }
      data={results}
      keyExtractor={(video) => video.id}
      ListEmptyComponent={
        normalizedQuery ? (
          <View style={styles.empty}>
            <Text style={styles.emptyText}>{strings.search.noResults(query)}</Text>
          </View>
        ) : undefined
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
  emptyContent: {
    flexGrow: 1,
  },
  empty: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 32,
  },
  emptyText: {
    color: PlatformColor('secondaryLabel'),
    fontSize: 15,
    textAlign: 'center',
  },
});
