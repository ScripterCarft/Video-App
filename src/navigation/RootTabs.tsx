import { createNativeBottomTabNavigator } from '@bottom-tabs/react-navigation';
import { HomeStack } from './HomeStack';
import { SearchStack } from './SearchStack';
import { SubscriptionsStack } from './SubscriptionsStack';
import { LibraryStack } from './LibraryStack';
import { useStrings } from '../i18n/strings';

const Tab = createNativeBottomTabNavigator();

export function RootTabs() {
  const strings = useStrings();

  return (
    <Tab.Navigator>
      <Tab.Screen
        name="HomeTab"
        component={HomeStack}
        options={{
          title: strings.tabs.home,
          tabBarIcon: () => ({ sfSymbol: 'house' }),
        }}
      />
      <Tab.Screen
        name="SearchTab"
        component={SearchStack}
        options={{
          title: strings.tabs.search,
          tabBarIcon: () => ({ sfSymbol: 'magnifyingglass' }),
        }}
      />
      <Tab.Screen
        name="SubscriptionsTab"
        component={SubscriptionsStack}
        options={{
          title: strings.tabs.subscriptions,
          tabBarIcon: () => ({ sfSymbol: 'person.2' }),
        }}
      />
      <Tab.Screen
        name="LibraryTab"
        component={LibraryStack}
        options={{
          title: strings.tabs.library,
          tabBarIcon: () => ({ sfSymbol: 'books.vertical' }),
        }}
      />
    </Tab.Navigator>
  );
}
