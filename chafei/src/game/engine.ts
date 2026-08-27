import { ENEMIES, GAME, type EnemyDef, type EnemyType } from './config';
import type { Enemy, Player, Projectile, Vec2 } from './types';

let nextId = 1;
function uid() {
  return nextId++;
}

export function resetId() {
  nextId = 1;
}

export function makePlayer(): Player {
  return {
    pos: { x: GAME.playerX, y: GAME.playerY },
    hp: GAME.playerMaxHp,
    maxHp: GAME.playerMaxHp,
    radius: GAME.playerRadius,
    attackTimer: 0,
    attackInterval: GAME.attackInterval,
    multiShot: 1,
    fanAngle: 0,
    critChance: 0,
    pierce: 1, // 0 -> 1: 基础穿透 1, 每发可贯穿 2 只, 清群关键
    damageMul: 1,
    speedMul: 1,
    inkRadiusMul: 1,
  };
}

function dist(a: Vec2, b: Vec2) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

function normalize(v: Vec2): Vec2 {
  const d = Math.sqrt(v.x * v.x + v.y * v.y) || 1;
  return { x: v.x / d, y: v.y / d };
}

function rotate(v: Vec2, deg: number): Vec2 {
  const rad = (deg * Math.PI) / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  return { x: v.x * cos - v.y * sin, y: v.x * sin + v.y * cos };
}

function rand(min: number, max: number) {
  return Math.random() * (max - min) + min;
}

function pickEnemyType(time: number): EnemyType {
  const roll = Math.random();
  if (time < 20) {
    return roll < 0.7 ? 'foam' : 'scorch';
  }
  if (time < 60) {
    if (roll < 0.45) return 'foam';
    if (roll < 0.8) return 'scorch';
    return 'thought';
  }
  if (roll < 0.35) return 'foam';
  if (roll < 0.65) return 'scorch';
  return 'thought';
}

function spawnOne(type: EnemyType, x?: number, hpMul = 1, speedMul = 1): Enemy {
  const def = ENEMIES[type];
  const startX = x ?? rand(40, GAME.width - 40);
  const baseY = -def.radius;
  let vel: Vec2 = { x: 0, y: def.speed * speedMul };

  if (type === 'scorch') {
    // 斜冲
    const targetX = rand(GAME.width * 0.25, GAME.width * 0.75);
    vel = normalize({ x: targetX - startX, y: GAME.height * 0.75 - baseY });
    vel = { x: vel.x * def.speed * speedMul, y: vel.y * def.speed * speedMul };
  } else if (type === 'thought') {
    vel = { x: rand(-10, 10), y: def.speed * speedMul };
  }

  return {
    id: uid(),
    type,
    pos: { x: startX, y: baseY },
    vel,
    hp: def.hp * hpMul,
    maxHp: def.hp * hpMul,
    radius: def.radius,
    damage: def.damage,
    ink: def.ink,
    color: def.color,
    age: 0,
    split: false,
    dead: false,
  };
}

export function difficultyAt(elapsed: number): number {
  // 参考 canvas-vampire-survivors: 每 60s 敌人强度 ×1.3
  // 2 分钟局: 1.0x -> 1.69x (原线性公式到 2.33x 太陡)
  return 1.3 ** (elapsed / 60);
}

export function spawnEnemies(
  _time: number,
  elapsed: number,
  rate: number
): Enemy[] {
  const spawned: Enemy[] = [];
  const difficulty = difficultyAt(elapsed); // 1x -> 1.69x at 120s
  const interval = rate / difficulty;
  let count = 0;
  if (Math.random() < (1 / Math.max(interval, 0.3))) {
    count = 1;
  }
  for (let i = 0; i < count; i++) {
    const type = pickEnemyType(elapsed);
    spawned.push(spawnOne(type, undefined, difficulty, difficulty ** 0.5));
  }
  return spawned;
}

export function findNearestEnemy(player: Player, enemies: Enemy[]): Enemy | null {
  let nearest: Enemy | null = null;
  let best = Infinity;
  for (const e of enemies) {
    if (e.dead) continue;
    const d = dist(player.pos, e.pos);
    if (d < best) {
      best = d;
      nearest = e;
    }
  }
  return nearest;
}

export function fireProjectiles(player: Player, target: Enemy | null): Projectile[] {
  const projectiles: Projectile[] = [];
  const origin = player.pos;
  const dir: Vec2 = target
    ? normalize({ x: target.pos.x - origin.x, y: target.pos.y - origin.y })
    : { x: 0, y: -1 };

  const count = Math.max(1, Math.floor(player.multiShot));
  const fan = player.fanAngle;
  const step = fan > 0 && count > 1 ? fan / (count - 1) : 0;
  const startAngle = -fan / 2;

  for (let i = 0; i < count; i++) {
    const angle = startAngle + i * step;
    const v = rotate(dir, angle);
    const speed = GAME.projectileSpeed * player.speedMul;
    projectiles.push({
      id: uid(),
      pos: { x: origin.x, y: origin.y - player.radius },
      vel: { x: v.x * speed, y: v.y * speed },
      damage: Math.round(GAME.projectileDamage * player.damageMul),
      life: 0,
      maxLife: 2.5,
      pierce: player.pierce,
      color: '#3b7a5c',
    });
  }
  return projectiles;
}

export function updatePlayer(
  player: Player,
  dt: number,
  enemies: Enemy[],
  projectiles: Projectile[]
) {
  player.attackTimer += dt;
  if (player.attackTimer >= player.attackInterval) {
    player.attackTimer = 0;
    const target = findNearestEnemy(player, enemies);
    projectiles.push(...fireProjectiles(player, target));
    // 限制同屏
    if (projectiles.length > GAME.maxProjectiles) {
      projectiles.splice(0, projectiles.length - GAME.maxProjectiles);
    }
  }
}

export function updateEnemies(
  enemies: Enemy[],
  dt: number,
  player: Player
): { damage: number; ink: number; spawned: Enemy[] } {
  let damage = 0;
  let ink = 0;
  const spawned: Enemy[] = [];

  for (let i = enemies.length - 1; i >= 0; i--) {
    const e = enemies[i];
    e.age += dt;

    // scorch 抖动
    if (e.type === 'scorch') {
      e.pos.x += Math.sin(e.age * 15) * 0.8;
    }
    e.pos.x += e.vel.x * dt;
    e.pos.y += e.vel.y * dt;

    if (e.pos.y - e.radius > GAME.height) {
      enemies.splice(i, 1);
      continue;
    }

    if (dist(e.pos, player.pos) <= e.radius + player.radius) {
      damage += e.damage;
      enemies.splice(i, 1);
      continue;
    }

    if (e.hp <= 0) {
      e.dead = true;
      ink += e.ink;
      if (e.type === 'thought' && !e.split) {
        e.split = true;
        for (let s = 0; s < 2; s++) {
          spawned.push(
            spawnOne(
              'thought',
              e.pos.x + rand(-12, 12),
              0.35,
              1.3
            )
          );
        }
      }
      enemies.splice(i, 1);
    }
  }

  return { damage, ink, spawned };
}

export function clampInk(ink: number): number {
  const cap = GAME.inkToLevel;
  return Math.min(ink, cap);
}
