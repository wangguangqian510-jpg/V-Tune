import type { Player, Upgrade, UpgradeCategory } from './types';

export const UPGRADE_TITLES: Record<UpgradeCategory, string> = {
  arcane: '奥术飞弹',
  ice: '冰锥术',
  log: '滚木',
  passive: '被动',
};

function makeUpgrade(
  id: string,
  category: UpgradeCategory,
  name: string,
  desc: string,
  apply: (p: Player) => void,
  requires?: (p: Player) => boolean
): Upgrade {
  return {
    id, category, name, desc,
    level: 1,
    maxLevel: 5,
    effect: apply,
    requires,
  };
}

// 兜底卡（全部升满后出现）
const FALLBACK_POOL: Omit<Upgrade, 'level'>[] = [
  {
    id: 'fb_damage', category: 'passive', name: '法力涌动', desc: '全伤害 +8%',
    maxLevel: 99, effect: p => { p.damageMul += 0.08; },
  },
  {
    id: 'fb_cdr', category: 'passive', name: '咒文熟练', desc: '全技能冷却 -6%',
    maxLevel: 99, effect: p => { p.cooldownMul = Math.max(0.5, p.cooldownMul * 0.94); },
  },
  {
    id: 'fb_crit', category: 'passive', name: '致命一击', desc: '暴击率 +5%',
    maxLevel: 99, effect: p => { p.critChance += 0.05; },
  },
];

export function buildUpgradePool(levels: Record<string, number>, player: Player): Upgrade[] {
  return [
    // === 奥术飞弹系 ===
    makeUpgrade('arcane_cast', 'arcane', '飞弹连发', '额外释放1次，伤害-20%', p => {
      p.extraCast += 1;
      p.damageMul *= 0.8;
    }),
    makeUpgrade('arcane_multi', 'arcane', '飞弹齐射', '子弹+1，伤害-20%', p => {
      p.multiShot += 1;
      p.damageMul *= 0.8;
    }),
    makeUpgrade('arcane_damage', 'arcane', '飞弹增伤', '飞弹伤害 +30%', p => {
      p.damageMul += 0.3;
    }),
    makeUpgrade('arcane_pierce', 'arcane', '飞弹穿透', '穿透 +1', p => {
      p.pierce += 1;
    }),
    makeUpgrade('arcane_fan', 'arcane', '飞弹散射', '散射角 +15°', p => {
      p.fanAngle += 15;
    }),

    // === 冰锥术系（需先学习冰锥） ===
    makeUpgrade('learn_ice', 'ice', '学习冰锥术', '解锁冰锥术（高伤直线）', p => {
      p.hasIce = true;
    }, p => !p.hasIce),
    makeUpgrade('ice_cast', 'ice', '冰锥连发', '冰锥额外释放1次', p => {
      // 通过降低冰锥冷却实现（简化处理）
      p.cooldownMul *= 0.9;
    }, p => p.hasIce),
    makeUpgrade('ice_pierce', 'ice', '冰锥贯穿', '冰锥伤害+30%，穿透+2', p => {
      p.damageMul += 0.15;
      p.pierce += 2;
    }, p => p.hasIce),

    // === 滚木系（需第5波后） ===
    makeUpgrade('learn_log', 'log', '学习滚木', '解锁滚木（宽横扫，穿透∞）', p => {
      p.hasLog = true;
    }),
    makeUpgrade('log_damage', 'log', '滚木增伤', '滚木伤害 +40%', p => {
      p.damageMul += 0.2;
    }, p => p.hasLog),

    // === 被动 ===
    makeUpgrade('cdr', 'passive', '冷却缩减', '全技能冷却 -10%', p => {
      p.cooldownMul = Math.max(0.4, p.cooldownMul * 0.9);
    }),
    makeUpgrade('repair', 'passive', '修复城墙', '城墙 HP +500', p => {
      // 实际修复在 App 层处理，这里标记
    }),
    makeUpgrade('crit', 'passive', '暴击强化', '暴击率 +8%', p => {
      p.critChance += 0.08;
    }),
    makeUpgrade('speed', 'passive', '咒文急速', '弹道速度 +15%', p => {
      p.speedMul += 0.15;
    }),
  ].map(u => {
    const lv = levels[u.id] ?? 0;
    const clone = { ...u, level: Math.min(lv + 1, u.maxLevel) };
    if (lv > 0) {
      clone.name = `${clone.name} Lv.${clone.level}`;
    }
    return clone;
  });
}

export function pickThree(levels: Record<string, number>, player: Player): Upgrade[] {
  const pool = buildUpgradePool(levels, player);
  const available = pool
    .filter(u => {
      if ((levels[u.id] ?? 0) >= u.maxLevel) return false;
      if (u.requires && !u.requires(player)) return false;
      return true;
    })
    .sort(() => Math.random() - 0.5);

  if (available.length >= 3) {
    return available.slice(0, 3);
  }

  // 不足3张用兜底卡补齐
  const result = [...available];
  const fbShuffled = [...FALLBACK_POOL].sort(() => Math.random() - 0.5);
  for (const fb of fbShuffled) {
    if (result.length >= 3) break;
    result.push({ ...fb, level: 1 });
  }
  return result;
}
