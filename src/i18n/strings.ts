import * as Localization from 'expo-localization';

const en = {
  tabs: {
    home: 'Home',
    search: 'Search',
    subscriptions: 'Subscriptions',
    library: 'Library',
  },
  search: {
    placeholder: 'Videos, channels',
    noResults: (query: string) => `No results for "${query}"`,
  },
  library: {
    showComments: 'Show comments',
  },
  video: {
    views: (label: string) => `${label} views`,
  },
  channel: {
    subscribers: (count: string, videoCount: number) =>
      `${count} subscribers · ${videoCount} videos`,
  },
};

// Add further locales here as they're translated, e.g. `const de = {...}`.
const translations = { en };

export type Locale = keyof typeof translations;
export type Strings = typeof en;

function resolveLocale(): Locale {
  const deviceLanguage = Localization.getLocales()[0]?.languageCode;
  return deviceLanguage && deviceLanguage in translations
    ? (deviceLanguage as Locale)
    : 'en';
}

export function useStrings(): Strings {
  return translations[resolveLocale()];
}
