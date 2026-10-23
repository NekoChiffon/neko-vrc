/// VRChat 资料页预设背景。
///
/// 模板 ID 和素材地址没有公开接口，这份清单对齐 VRCX 的
/// src/shared/constants/backgrounds.js（素材都在 assets.vrchat.com）。
class ProfileBackgroundPreset {
  const ProfileBackgroundPreset({
    required this.id,
    required this.label,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.isVrcPlus,
  });

  final String id;
  final String label;

  /// 铺满资料页的大图。
  final String imageUrl;

  /// 选择器里用的小图。
  final String thumbnailUrl;

  final bool isVrcPlus;
}

const profileBackgroundPresets = <ProfileBackgroundPreset>[
  ProfileBackgroundPreset(
    id: 'grid',
    label: 'Grid',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Grid.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Grid_Thumb.png',
    isVrcPlus: false,
  ),
  ProfileBackgroundPreset(
    id: 'filigree',
    label: 'Filigree',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Cascade.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Cascade_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'bit-mountain',
    label: 'Bit Mountain',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_GRID_BITS.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_GRID_BITS_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'approach',
    label: 'Approach',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Approach.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Approach_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'planet-fall',
    label: 'Planet Fall',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_PlanetFall.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_PlanetFall_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'jungle',
    label: 'Jungle',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Jungle.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Jungle_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'light-streams',
    label: 'Light Streams',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_LightStream.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_LightStream_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'koi',
    label: 'Koi',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/Koi_Layer.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/Koi_Layer_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'moonlight',
    label: 'Moonlight',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Cloud.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Cloud_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'machine',
    label: 'Machine',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/TechWallLayer.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/TechWallLayer_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'topology',
    label: 'Topology',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/TOPOLOGY.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/TOPOLOGY_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'circuit',
    label: 'Circuit',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Circuit.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Circuit_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'kawaii-cupcakes',
    label: 'Kawaii Cupcakes',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Kawaii_cupcakes.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Kawaii_cupcakes_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'bokeh',
    label: 'Bokeh',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Bokeh.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Bokeh_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'hologram',
    label: 'Hologram',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Shatter.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Shatter_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'flow',
    label: 'Flow',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Flow_Horizontal.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Flow_Horizontal_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'jelly',
    label: 'Jelly',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Jelly.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Jelly_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'cheese',
    label: 'Cheese',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Cheese.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Cheese_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'alchemy',
    label: 'Alchemy',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Alchemy.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Alchemy_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'sunset-mountain',
    label: 'Sunset Mountain',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_MountainSun.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_MountainSun_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'magic-rocks',
    label: 'Magic Rocks',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_MagicRocks.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_MagicRocks_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'city-stillness',
    label: 'City Stillness',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_FutureCityStillness.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_FutureCityStillness_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'music',
    label: 'Music',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Music.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Music_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'wolf-running',
    label: 'Wolf Running',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_WolfRunning.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_WolfRunning_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'dragon-smoke',
    label: 'Dragon Smoke',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_DragonSmoke.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_DragonSmoke_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'night-rain',
    label: 'Night Rain',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_NightRain.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_NightRain_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'butterfly-zero',
    label: 'Butterfly Zero',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_ButterFlyZERO.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_ButterFlyZERO_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'i-am-speed',
    label: 'I Am Speed',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/void.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/void_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'ronin',
    label: 'Ronin',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Ronin.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Ronin_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'abduction',
    label: 'Abduction',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Abduction.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Abduction_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'cat-dream',
    label: 'Cat Dream',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_CatDream.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_CatDream_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'virtual-waves',
    label: 'Virtual Waves',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_VirtualWaves.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_VirtualWaves_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'bolt-and-snail',
    label: 'Bolt and Snail',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_BoltNSnail.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_BoltNSnail_Thumb.png',
    isVrcPlus: true,
  ),
  ProfileBackgroundPreset(
    id: 'escape',
    label: 'Escape',
    imageUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Escape.png',
    thumbnailUrl: 'https://assets.vrchat.com/www/profile_decorations/profile_backgrounds/BG_Escape_Thumb.png',
    isVrcPlus: true,
  ),
];

ProfileBackgroundPreset? profileBackgroundPreset(String id) {
  for (final preset in profileBackgroundPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
