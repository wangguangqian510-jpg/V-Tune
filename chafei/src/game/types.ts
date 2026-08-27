import type { EnemyType } from './config';

export interface Vec2 {
  x: number;
  y: number;
}

export interface Enemy {
  id: number;
  type: EnemyType;
  pos: Vec2;
  vel: Vec2;
  hp: number;
  maxHp: number;
  radius: number;
  damage: number;
  ink: number;
  color: string;
  age: number;
  split: boolean;
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
}

export interface Player {
  pos: Vec2;
  hp: number;
  maxHp: number;
  radius: number;
  attackTimer: number;
  attackInterval: number;
  multiShot: number;
  fanAngle: number;
  critChance: number;
  pierce: number;
  damageMul: number;
  speedMul: number;
  inkRadiusMul: number;
}

export type UpgradeCategory = 'tea' | 'method' | 'mind';

export interface Upgrade {
  id: string;
  category: UpgradeCategory;
  name: string;
  desc: string;
  level: number;
  maxLevel: number;
  effect: (p: Player) => void;
}

export type GameState = 'playing' | 'paused' | 'upgrade' | 'won' | 'lost';
