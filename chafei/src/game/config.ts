export const COLORS = {
  paper: '#f3efe4',
  paperLight: '#f7f3ea',
  ink: '#1a1a1a',
  inkGray: '#5f5e5a',
  cinnabar: '#c0392b',
  teal: '#3b7a5c',
  tealLight: '#5d9e7b',
  ochre: '#b07a3c',
  fire: '#d85a30',
  ash: '#888780',
};

export const GAME = {
  width: 390,
  height: 844,
  duration: 120, // seconds
  playerMaxHp: 100,
  playerX: 195,
  playerY: 720,
  playerRadius: 28,
  attackInterval: 0.55, // base seconds
  projectileSpeed: 520, // px per second
  projectileDamage: 14,
  inkPerKill: 12,
  inkToLevel: 100, // 兼容字段，实际用 LEVEL.expForLevel
  maxProjectiles: 28,
  spawnRateInitial: 1.5, // seconds
};

// 等级系统：上限 10 级，经验曲线 20 + level*30
// L1→2:50  L2→3:80  L3→4:110  L4→5:140  L5→6:170  L6→7:200  L7→8:230  L8→9:260  L9→10:290
// 总计 1530 经验，2 分钟内约 100-130 击杀 × 平均 15 经验 ≈ 1500-1950，刚好满级
export const LEVEL = {
  maxLevel: 10,
  expForLevel: (level: number) => 20 + level * 30,
  // 敌人下降速度随等级提升：每级 +6%，10 级时 +54%
  speedMulForLevel: (level: number) => 1 + (level - 1) * 0.06,
};

export type EnemyType = 'foam' | 'scorch' | 'thought';

export interface EnemyDef {
  type: EnemyType;
  hp: number;
  speed: number;
  radius: number;
  damage: number;
  ink: number;
  color: string;
  split?: number;
  waveOffset?: number;
}

export const ENEMIES: Record<EnemyType, EnemyDef> = {
  foam: {
    type: 'foam',
    hp: 16, // 18 -> 16
    speed: 55, // 90 -> 55: 下降明显放缓
    radius: 14,
    damage: 7, // 8 -> 7
    ink: 10,
    color: COLORS.tealLight,
  },
  scorch: {
    type: 'scorch',
    hp: 25, // 28 -> 25
    speed: 78, // 110 -> 78: 斜冲放缓
    radius: 18,
    damage: 10, // 12 -> 10
    ink: 14,
    color: COLORS.fire,
    waveOffset: 1,
  },
  thought: {
    type: 'thought',
    hp: 32, // 35 -> 32
    speed: 40, // 55 -> 40: 重甲慢速
    radius: 22,
    damage: 12, // 15 -> 12
    ink: 22,
    color: COLORS.ash,
    split: 2,
  },
};
