import { createNativeBottomTabNavigator } from '@bottom-tabs/react-navigation';
import { HomeStack } from './HomeStack';
import { SearchStack } from './SearchStack';
import { SubscriptionsStack } from './SubscriptionsStack';
import { LibraryStack } from './LibraryStack';

const Tab = createNativeBottomTabNavigator();

export function RootTabs() {
  return (
    <Tab.Navigator>
      <Tab.Screen
        name="HomeTab"
        component={HomeStack}
        options={{
          title: 'Home',
          tabBarIcon: () => ({ sfSymbol: 'house' }),
        }}
      />
      <Tab.Screen
        name="SearchTab"
        component={SearchStack}
        options={{
          title: 'Suchen',
          tabBarIcon: () => ({ sfSymbol: 'magnifyingglass' }),
        }}
      />
      <Tab.Screen
        name="SubscriptionsTab"
        component={SubscriptionsStack}
        options={{
          title: 'Abos',
          tabBarIcon: () => ({ sfSymbol: 'person.2' }),
        }}
      />
      <Tab.Screen
        name="LibraryTab"
        component={LibraryStack}
        options={{
          title: 'Mediathek',
          tabBarIcon: () => ({ sfSymbol: 'books.vertical' }),
        }}
      />
    </Tab.Navigator>
  );
}
