#pragma once

// The generated autolinking.cpp includes <SplitflapViewSpec.h> (libraryName), calls the module
// provider and registers every descriptor listed in react-native.config.js. This header shadows
// codegen's own SplitflapViewSpec.h, so it has to declare the provider that codegen defines in
// SplitflapViewSpec-generated.cpp, and it brings in the custom descriptor, which lives in cpp/.

#include <ReactCommon/JavaTurboModule.h>
#include <ReactCommon/TurboModule.h>
#include <jsi/jsi.h>
#include <SplitflapViewComponentDescriptor.h>

namespace facebook::react {

JSI_EXPORT
std::shared_ptr<TurboModule> SplitflapViewSpec_ModuleProvider(
    const std::string &moduleName,
    const JavaTurboModule::InitParams &params);

} // namespace facebook::react
