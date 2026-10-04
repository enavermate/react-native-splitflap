/**
 * Android registers the custom C++ component descriptor (own measure) through autolinking:
 * the generated autolinking.cpp includes <SplitflapViewSpec.h> and adds every listed descriptor.
 * @type {import('@react-native-community/cli-types').UserDependencyConfig}
 */
module.exports = {
  dependency: {
    platforms: {
      android: {
        libraryName: 'SplitflapViewSpec',
        componentDescriptors: ['SplitflapViewComponentDescriptor'],
        cmakeListsPath: 'src/main/jni/CMakeLists.txt',
      },
    },
  },
};
