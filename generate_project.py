#!/usr/bin/env python3
"""Generate a minimal but valid Xcode project.pbxproj for JukeboxPlayer.

Run from the directory that contains this script (the repo root).
The produced project mirrors what Xcode creates for a SwiftUI iOS app.
"""
import os

REPO = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(REPO, "JukeboxPlayer.xcodeproj", "project.pbxproj")

_counter = [0]
def uid():
    _counter[0] += 1
    return format(_counter[0], "024X")

# logical name -> uuid
ids = {}
def gid(name):
    if name not in ids:
        ids[name] = uid()
    return ids[name]

# Sources (file path relative to repo root)
sources = [
    "JukeboxPlayer/App/JukeboxPlayerApp.swift",
    "JukeboxPlayer/App/PlayerEngine.swift",
    "JukeboxPlayer/Models/Track.swift",
    "JukeboxPlayer/Views/ContentView.swift",
    "JukeboxPlayer/Views/LibraryView.swift",
    "JukeboxPlayer/Views/TrackRow.swift",
    "JukeboxPlayer/Views/NowPlayingBar.swift",
    "JukeboxPlayer/Views/NowPlayingView.swift",
    "JukeboxPlayer/Core/Jukebox.swift",
    "JukeboxPlayer/Models/TrackStore.swift",
]
resources = ["JukeboxPlayer/Assets.xcassets"]
info_plist = "JukeboxPlayer/Resources/Info.plist"

for s in sources:
    gid("fr:" + s)
for r in resources:
    gid("fr:" + r)
gid("fr:" + info_plist)

# groups
app_group      = gid("grp:app")
models_group   = gid("grp:models")
views_group    = gid("grp:views")
core_group     = gid("grp:core")
res_group      = gid("grp:res")
products_group = gid("grp:products")
root_group     = gid("grp:root")

# build files
for s in sources:
    gid("bf:" + s)
gid("bf:assets")  # Assets.xcassets in Resources

# phases / target / project / configs
sources_phase  = gid("phase:sources")
fw_phase       = gid("phase:fw")
res_phase      = gid("phase:res")
target         = gid("target")
project        = gid("project")
proj_bcl       = gid("bcl:proj")
target_bcl     = gid("bcl:target")
proj_debug     = gid("cfg:proj_debug")
proj_release   = gid("cfg:proj_release")
tgt_debug      = gid("cfg:tgt_debug")
tgt_release    = gid("cfg:tgt_release")
product_ref    = gid("product")

def pbx_file_refs():
    lines = []
    for s in sources:
        u = ids["fr:" + s]
        name = os.path.basename(s)
        lines.append(f'\t\t{ u } /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }};')
    for r in resources:
        u = ids["fr:" + r]
        name = os.path.basename(r)
        lines.append(f'\t\t{ u } /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "{name}"; sourceTree = "<group>"; }};')
    u = ids["fr:" + info_plist]
    lines.append(f'\t\t{ u } /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};')
    lines.append(f'\t\t{ product_ref } /* JukeboxPlayer.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = JukeboxPlayer.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
    return "\n".join(lines)

def pbx_build_files():
    lines = []
    for s in sources:
        bf = ids["bf:" + s]
        fr = ids["fr:" + s]
        name = os.path.basename(s)
        lines.append(f'\t\t{ bf } /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = { fr } /* {name} */; }};')
    bf = ids["bf:assets"]
    fr = ids["fr:JukeboxPlayer/Assets.xcassets"]
    lines.append(f'\t\t{ bf } /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = { fr } /* Assets.xcassets */; }};')
    return "\n".join(lines)

src_build_files = ",\n".join(
    f'\t\t\t{ ids["bf:"+s] } /* {os.path.basename(s)} in Sources */' for s in sources
)
res_build_files = f'\t\t\t{ ids["bf:assets"] } /* Assets.xcassets in Resources */'

def groups():
    assets_ref = ids["fr:JukeboxPlayer/Assets.xcassets"]
    info_ref = ids["fr:" + info_plist]
    g = []
    g.append(f'\t\t{ root_group } = {{isa = PBXGroup; children = (\n\t\t\t{ app_group },\n\t\t\t{ models_group },\n\t\t\t{ views_group },\n\t\t\t{ core_group },\n\t\t\t{ res_group },\n\t\t\t{ assets_ref },\n\t\t\t{ products_group },\n\t\t); name = JukeboxPlayer; path = JukeboxPlayer; sourceTree = "<group>"; }};')
    g.append(f'\t\t{ app_group } = {{isa = PBXGroup; children = (\n\t\t\t{ ids["fr:JukeboxPlayer/App/JukeboxPlayerApp.swift"] },\n\t\t\t{ ids["fr:JukeboxPlayer/App/PlayerEngine.swift"] },\n\t\t); name = App; path = App; sourceTree = "<group>"; }};')
    g.append(f'\t\t{ models_group } = {{isa = PBXGroup; children = (\n\t\t\t{ ids["fr:JukeboxPlayer/Models/Track.swift"] },\n\t\t\t{ ids["fr:JukeboxPlayer/Models/TrackStore.swift"] },\n\t\t); name = Models; path = Models; sourceTree = "<group>"; }};')
    g.append(f'\t\t{ views_group } = {{isa = PBXGroup; children = (\n\t\t\t{ ids["fr:JukeboxPlayer/Views/ContentView.swift"] },\n\t\t\t{ ids["fr:JukeboxPlayer/Views/LibraryView.swift"] },\n\t\t\t{ ids["fr:JukeboxPlayer/Views/TrackRow.swift"] },\n\t\t\t{ ids["fr:JukeboxPlayer/Views/NowPlayingBar.swift"] },\n\t\t\t{ ids["fr:JukeboxPlayer/Views/NowPlayingView.swift"] },\n\t\t); name = Views; path = Views; sourceTree = "<group>"; }};')
    g.append(f'\t\t{ core_group } = {{isa = PBXGroup; children = (\n\t\t\t{ ids["fr:JukeboxPlayer/Core/Jukebox.swift"] },\n\t\t); name = Core; path = Core; sourceTree = "<group>"; }};')
    g.append(f'\t\t{ res_group } = {{isa = PBXGroup; children = (\n\t\t\t{ info_ref },\n\t\t); name = Resources; path = Resources; sourceTree = "<group>"; }};')
    g.append(f'\t\t{ products_group } = {{isa = PBXGroup; children = (\n\t\t\t{ product_ref },\n\t\t); name = Products; sourceTree = "<group>"; }};')
    return "\n".join(g)

proj_debug_settings = """\
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ( "DEBUG=1", "$(inherited)" );
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";"""

proj_release_settings = """\
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES;"""

tgt_debug_settings = """\
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = "JukeboxPlayer/Resources/Info.plist";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ( "$(inherited)", "@executable_path/Frameworks" );
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.arammo.cycomm;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";"""

tgt_release_settings = tgt_debug_settings + """
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES"""

pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{pbx_build_files()}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{pbx_file_refs()}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{ fw_phase } /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (
\t\t); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{groups()}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{ target } /* JukeboxPlayer */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = { target_bcl } /* Build configuration list for PBXNativeTarget "JukeboxPlayer" */;
\t\t\tbuildPhases = (
\t\t\t\t{ sources_phase } /* Sources */,
\t\t\t\t{ fw_phase } /* Frameworks */,
\t\t\t\t{ res_phase } /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = JukeboxPlayer;
\t\t\tproductName = JukeboxPlayer;
\t\t\tproductReference = { product_ref } /* JukeboxPlayer.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{ project } /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{ target } = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = { proj_bcl } /* Build configuration list for PBXProject "JukeboxPlayer" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = ( en, Base, "zh-Hans" );
\t\t\tmainGroup = { root_group };
\t\t\tproductRefGroup = { products_group } /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{ target } /* JukeboxPlayer */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{ res_phase } /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{res_build_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{ sources_phase } /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{src_build_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{ proj_debug } /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{proj_debug_settings}
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ proj_release } /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{proj_release_settings}
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{ tgt_debug } /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{tgt_debug_settings}
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ tgt_release } /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{tgt_release_settings}
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{ proj_bcl } /* Build configuration list for PBXProject "JukeboxPlayer" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ proj_debug } /* Debug */,
\t\t\t\t{ proj_release } /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{ target_bcl } /* Build configuration list for PBXNativeTarget "JukeboxPlayer" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ tgt_debug } /* Debug */,
\t\t\t\t{ tgt_release } /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = { project } /* Project object */;
}}
"""

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write(pbx)
print("wrote", OUT, "(", len(pbx), "bytes )")
