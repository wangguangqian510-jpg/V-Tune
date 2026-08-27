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
  attackInterval: 0.9, // base seconds
  projectileSpeed: 420, // px per second
  projectileDamage: 10,
  inkPerKill: 12,
  inkToLevel: 100,
  maxProjectiles: 18,
  spawnRateInitial: 1.2, // seconds
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
    hp: 18,
    speed: 90,
    radius: 14,
    damage: 8,
    ink: 10,
    color: COLORS.tealLight,
  },
  scorch: {
    type: 'scorch',
    hp: 28,
    speed: 110,
    radius: 18,
    damage: 12,
    ink: 14,
    color: COLORS.fire,
    waveOffset: 1,
  },
  thought: {
    type: 'thought',
    hp: 35,
    speed: 55,
    radius: 22,
    damage: 15,
    ink: 22,
    color: COLORS.ash,
    split: 2,
  },
};
