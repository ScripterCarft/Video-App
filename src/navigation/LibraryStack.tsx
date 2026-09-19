import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { LibraryScreen } from '../screens/LibraryScreen';
import { useStrings } from '../i18n/strings';

const Stack = createNativeStackNavigator();

export function LibraryStack() {
  const strings = useStrings();

  return (
    <Stack.Navigator>
      <Stack.Screen
        name="Library"
        component={LibraryScreen}
        options={{
          title: strings.tabs.library,
          headerLargeTitleEnabled: true,
          scrollEdgeEffects: { top: 'soft' },
        }}
      />
    </Stack.Navigator>
  );
}
