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
  attackInterval: 0.55, // base seconds (0.9 -> 0.55: 射速 ~66% 提升)
  projectileSpeed: 520, // px per second (420 -> 520: 弹速更跟手)
  projectileDamage: 14, // (10 -> 14: 单发伤害 +40%, 秒伤 ~11 -> ~25)
  inkPerKill: 12,
  inkToLevel: 100,
  maxProjectiles: 28, // (18 -> 28: 同屏弹量放宽)
  spawnRateInitial: 1.5, // seconds (1.2 -> 1.5: 初始生成放缓, 更解压)
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
