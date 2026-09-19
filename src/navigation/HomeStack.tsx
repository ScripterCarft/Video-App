import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { HomeScreen } from '../screens/HomeScreen';
import { useStrings } from '../i18n/strings';

const Stack = createNativeStackNavigator();

export function HomeStack() {
  const strings = useStrings();

  return (
    <Stack.Navigator>
      <Stack.Screen
        name="Home"
        component={HomeScreen}
        options={{
          title: strings.tabs.home,
          headerLargeTitleEnabled: true,
          headerTransparent: true,
        }}
      />
    </Stack.Navigator>
  );
}
