import type { EnemyType } from './config';

export interface Vec2 {
  x: number;
  y: number;
}

export type EnemyState = 'sleeping' | 'moving' | 'raging' | 'dead';

export interface Enemy {
  id: number;
  type: EnemyType;
  pos: Vec2;
  vel: Vec2;
  hp: number;
  maxHp: number;
  radius: number;
  damage: number;
  exp: number;
  color: string;
  age: number;
  state: EnemyState;
  sleepTimer: number; // 飘云怪剩余睡眠时间
  partnerId: number; // 双子面关联ID，-1 表示无
  dead: boolean;
}

export interface Projectile {
  id: number;
  pos: Vec2;
  vel: Vec2;
  damage: number;
  life: number;
  maxLife: number;
  pierce: number;
  color: string;
  kind: 'arcane' | 'ice' | 'log';
}

export interface Player {
  pos: Vec2;
  radius: number;
  level: number;
  exp: number;
  attackTimer: number;
  attackInterval: number;
  multiShot: number; // 飞弹齐射：子弹+N
  extraCast: number; // 飞弹连发：额外释放N次
  fanAngle: number;
  critChance: number;
  pierce: number;
  damageMul: number;
  speedMul: number;
  cooldownMul: number; // 全技能CD缩减
  // 已学习技能
  hasIce: boolean;
  hasLog: boolean;
  iceTimer: number;
  logTimer: number;
}

export type UpgradeCategory = 'arcane' | 'ice' | 'log' | 'passive';

export interface Upgrade {
  id: string;
  category: UpgradeCategory;
  name: string;
  desc: string;
  level: number;
  maxLevel: number;
  effect: (p: Player) => void;
  requires?: (p: Player) => boolean; // 前置条件
}

export type GameState = 'menu' | 'playing' | 'paused' | 'upgrade' | 'won' | 'lost';
