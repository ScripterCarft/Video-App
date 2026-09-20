import { Platform } from 'react-native';

export const homeIcon = () =>
  Platform.select({
    ios: { type: 'sfSymbol', name: 'house.fill' } as const,
    default: { type: 'image', source: { uri: 'ic_home' } } as const,
  });

export const searchIcon = () =>
  Platform.select({
    ios: { type: 'sfSymbol', name: 'magnifyingglass' } as const,
    default: { type: 'image', source: { uri: 'ic_search' } } as const,
  });

export const libraryIcon = () =>
  Platform.select({
    ios: { type: 'sfSymbol', name: 'square.stack.fill' } as const,
    default: { type: 'image', source: { uri: 'ic_video_library' } } as const,
  });

export const followingIcon = () =>
  Platform.select({
    ios: { type: 'sfSymbol', name: 'person.2.fill' } as const,
    default: { type: 'image', source: { uri: 'ic_following' } } as const,
  });
