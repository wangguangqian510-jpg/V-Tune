import { ENEMIES, GAME, LEVEL, WAVES, type EnemyDef, type EnemyType } from './config';
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
    radius: GAME.playerRadius,
    level: 1,
    exp: 0,
    attackTimer: 0,
    attackInterval: GAME.attackInterval,
    multiShot: 1,
    extraCast: 0,
    fanAngle: 0,
    critChance: 0,
    pierce: 0,
    damageMul: 1,
    speedMul: 1,
    cooldownMul: 1,
    hasIce: false,
    hasLog: false,
    iceTimer: 0,
    logTimer: 0,
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

// 当前波次
export function currentWave(elapsed: number): number {
  return Math.min(WAVES.total, Math.floor(elapsed / WAVES.durationPerWave) + 1);
}

// 选怪：根据波次决定出现哪些类型
function pickEnemyType(wave: number): EnemyType {
  const roll = Math.random();
  if (wave <= 2) {
    return 'imp'; // 前2波只有小鬼面
  }
  if (wave <= 4) {
    return roll < 0.75 ? 'imp' : 'cloud';
  }
  if (wave <= 5) {
    return roll < 0.5 ? 'imp' : roll < 0.8 ? 'cloud' : 'twin';
  }
  // 第6波后全类型
  if (roll < 0.4) return 'imp';
  if (roll < 0.65) return 'cloud';
  return 'twin';
}

function spawnOne(
  type: EnemyType,
  wave: number,
  x?: number,
  partnerId: number = -1
): Enemy {
  const def = ENEMIES[type];
  const hpScale = WAVES.hpScale(wave);
  const dmgScale = WAVES.damageScale(wave);
  const startX = x ?? rand(40, GAME.width - 40);
  const baseY = -def.radius - 10;

  let vel: Vec2 = { x: 0, y: def.speed };
  if (type === 'twin') {
    vel = { x: rand(-15, 15), y: def.speed };
  }

  const isSleeping = type === 'cloud';

  return {
    id: uid(),
    type,
    pos: { x: startX, y: baseY },
    vel,
    hp: def.hp * hpScale,
    maxHp: def.hp * hpScale,
    radius: def.radius,
    damage: def.damage * dmgScale,
    exp: def.exp,
    color: def.color,
    age: 0,
    state: isSleeping ? 'sleeping' : 'moving',
    sleepTimer: isSleeping ? (def.sleepDuration ?? 3) : 0,
    partnerId,
    dead: false,
  };
}

// 生成敌人（含双子配对、精英）
export function spawnEnemies(elapsed: number, wave: number): Enemy[] {
  const spawned: Enemy[] = [];
  const type = pickEnemyType(wave);

  if (type === 'twin') {
    // 双子面：成对生成，互相关联
    const baseX = rand(60, GAME.width - 60);
    const id1 = uid();
    const id2 = uid();
    const e1 = spawnOne('twin', wave, baseX - 18, id2);
    e1.id = id1;
    const e2 = spawnOne('twin', wave, baseX + 18, id1);
    e2.id = id2;
    spawned.push(e1, e2);
  } else {
    spawned.push(spawnOne(type, wave));
  }

  // 精英波：额外生成墨团精英
  if (WAVES.eliteWaves.includes(wave)) {
    // 只在波次开始时生成一次（elapsed 刚好是波次起始）
    const waveStart = (wave - 1) * WAVES.durationPerWave;
    if (elapsed - waveStart < 0.5) {
      const eliteCount = wave === 20 ? 2 : 1;
      for (let i = 0; i < eliteCount; i++) {
        spawned.push(spawnOne('ink_elite', wave, GAME.width / 2 + (i - 0.5) * 80));
      }
    }
  }

  return spawned;
}

// 瞄准：优先最危险（最靠近城墙/底部）的敌人
export function findTargetEnemy(player: Player, enemies: Enemy[]): Enemy | null {
  let target: Enemy | null = null;
  let bestScore = -Infinity;
  for (const e of enemies) {
    if (e.dead || e.state === 'sleeping') continue;
    const vertical = e.pos.y;
    const horizontalDist = Math.abs(e.pos.x - player.pos.x);
    const score = vertical - horizontalDist * 0.2;
    if (score > bestScore) {
      bestScore = score;
      target = e;
    }
  }
  return target;
}

// 发射奥术飞弹
export function fireArcane(player: Player, target: Enemy | null): Projectile[] {
  const projectiles: Projectile[] = [];
  const origin = player.pos;
  const dir: Vec2 = target
    ? normalize({ x: target.pos.x - origin.x, y: target.pos.y - origin.y })
    : { x: 0, y: -1 };

  const casts = 1 + player.extraCast;
  const count = Math.max(1, Math.floor(player.multiShot));
  const fan = player.fanAngle;
  const step = fan > 0 && count > 1 ? fan / (count - 1) : 0;
  const startAngle = -fan / 2;

  for (let c = 0; c < casts; c++) {
    for (let i = 0; i < count; i++) {
      const angle = startAngle + i * step;
      const v = rotate(dir, angle);
      const speed = GAME.projectileSpeed * player.speedMul;
      // 连发有微小偏移，避免完全重叠
      const offsetX = c * 6;
      projectiles.push({
        id: uid(),
        pos: { x: origin.x + offsetX, y: origin.y - player.radius },
        vel: { x: v.x * speed, y: v.y * speed },
        damage: Math.round(GAME.projectileDamage * player.damageMul),
        life: 0,
        maxLife: 2.5,
        pierce: player.pierce,
        color: '#6B5B95',
        kind: 'arcane',
      });
    }
  }
  return projectiles;
}

// 发射冰锥（直线，高伤）
export function fireIce(player: Player, target: Enemy | null): Projectile[] {
  const origin = player.pos;
  const dir: Vec2 = target
    ? normalize({ x: target.pos.x - origin.x, y: target.pos.y - origin.y })
    : { x: 0, y: -1 };
  const speed = 380 * player.speedMul;
  return [{
    id: uid(),
    pos: { x: origin.x, y: origin.y - player.radius },
    vel: { x: dir.x * speed, y: dir.y * speed },
    damage: Math.round(25 * player.damageMul),
    life: 0,
    maxLife: 2.5,
    pierce: player.pierce,
    color: '#4A90D9',
    kind: 'ice',
  }];
}

// 发射滚木（宽横扫，穿透∞）
export function fireLog(player: Player): Projectile[] {
  const origin = player.pos;
  const speed = 300;
  return [{
    id: uid(),
    pos: { x: origin.x, y: origin.y - player.radius - 20 },
    vel: { x: 0, y: -speed },
    damage: Math.round(35 * player.damageMul),
    life: 0,
    maxLife: 3.0,
    pierce: 999, // 滚木穿透∞
    color: '#8B6914',
    kind: 'log',
  }];
}

export function updatePlayer(
  player: Player,
  dt: number,
  enemies: Enemy[],
  projectiles: Projectile[]
) {
  const cd = player.cooldownMul;

  // 奥术飞弹（主技能）
  player.attackTimer += dt;
  if (player.attackTimer >= player.attackInterval * cd) {
    player.attackTimer = 0;
    const target = findTargetEnemy(player, enemies);
    projectiles.push(...fireArcane(player, target));
  }

  // 冰锥术
  if (player.hasIce) {
    player.iceTimer += dt;
    if (player.iceTimer >= 1.6 * cd) {
      player.iceTimer = 0;
      const target = findTargetEnemy(player, enemies);
      projectiles.push(...fireIce(player, target));
    }
  }

  // 滚木
  if (player.hasLog) {
    player.logTimer += dt;
    if (player.logTimer >= 3.0 * cd) {
      player.logTimer = 0;
      projectiles.push(...fireLog(player));
    }
  }

  // 同屏弹量限制
  if (projectiles.length > GAME.maxProjectiles) {
    projectiles.splice(0, projectiles.length - GAME.maxProjectiles);
  }
}

export function updateEnemies(
  enemies: Enemy[],
  dt: number,
  player: Player
): { damage: number; exp: number; spawned: Enemy[] } {
  let damage = 0;
  let exp = 0;
  const spawned: Enemy[] = [];

  for (let i = enemies.length - 1; i >= 0; i--) {
    const e = enemies[i];
    e.age += dt;

    // 飘云怪：睡眠时间递减，到点醒来
    if (e.state === 'sleeping') {
      e.sleepTimer -= dt;
      if (e.sleepTimer <= 0) {
        e.state = 'moving';
      }
      // 睡觉时缓慢飘动
      e.pos.x += Math.sin(e.age * 2) * 8 * dt;
    } else {
      // 移动
      e.pos.x += e.vel.x * dt;
      e.pos.y += e.vel.y * dt;
    }

    // 超出屏幕底部（飞过城墙）
    if (e.pos.y - e.radius > GAME.height) {
      enemies.splice(i, 1);
      continue;
    }

    // 撞城墙判定线
    if (e.pos.y + e.radius >= GAME.wallLineY) {
      damage += e.damage;
      enemies.splice(i, 1);
      continue;
    }

    // 死亡处理
    if (e.hp <= 0) {
      e.dead = true;
      e.state = 'dead';
      exp += e.exp;

      // 双子面：一个死了，另一个狂暴（+50%速）
      if (e.type === 'twin' && e.partnerId >= 0) {
        for (const other of enemies) {
          if (other.id === e.partnerId && !other.dead) {
            other.state = 'raging';
            other.vel.y *= 1.5;
            other.vel.x *= 1.5;
          }
        }
      }

      enemies.splice(i, 1);
    }
  }

  return { damage, exp, spawned };
}
