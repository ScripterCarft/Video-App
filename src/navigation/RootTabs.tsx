import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { HomeStack } from './HomeStack';
import { SearchStack } from './SearchStack';
import { SubscriptionsStack } from './SubscriptionsStack';
import { LibraryStack } from './LibraryStack';
import { useStrings } from '../i18n/strings';

export type RootTabParamList = {
  HomeTab: undefined;
  SubscriptionsTab: undefined;
  LibraryTab: undefined;
  SearchTab: undefined;
};

const Tab = createBottomTabNavigator<RootTabParamList>();

export function RootTabs() {
  const strings = useStrings();

  return (
    <Tab.Navigator implementation="native">
      <Tab.Screen
        name="HomeTab"
        component={HomeStack}
        options={{
          title: strings.tabs.home,
          tabBarIcon: () => ({
            type: 'sfSymbol',
            name: 'house.fill',
          }),
        }}
      />
      <Tab.Screen
        name="SubscriptionsTab"
        component={SubscriptionsStack}
        options={{
          title: strings.tabs.subscriptions,
          tabBarIcon: () => ({
            type: 'sfSymbol',
            name: 'person.2.fill',
          }),
        }}
      />
      <Tab.Screen
        name="LibraryTab"
        component={LibraryStack}
        options={{
          title: strings.tabs.library,
          tabBarIcon: () => ({
            type: 'sfSymbol',
            name: 'rectangle.stack.fill',
          }),
        }}
      />
      <Tab.Screen
        name="SearchTab"
        component={SearchStack}
        options={{
          title: strings.tabs.search,
          tabBarSystemItem: 'search',
        }}
      />
    </Tab.Navigator>
  );
}
