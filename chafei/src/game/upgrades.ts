import type { Player, Upgrade, UpgradeCategory } from './types';

export const UPGRADE_TITLES: Record<UpgradeCategory, string> = {
  tea: '茶种',
  method: '手法',
  mind: '心境',
};

function makeUpgrade(
  id: string,
  category: UpgradeCategory,
  name: string,
  desc: string,
  apply: (p: Player) => void
): Upgrade {
  return {
    id,
    category,
    name,
    desc,
    level: 1,
    maxLevel: 5,
    effect: apply,
  };
}

export function buildUpgradePool(levels: Record<string, number>): Upgrade[] {
  return [
    // 茶种：龙井穿透 / 普洱溅射 / 白毫连射
    makeUpgrade('longjing', 'tea', '龙井', '水线穿透+1，可贯穿更多浮沫', p => {
      p.pierce += 1;
      p.damageMul += 0.15;
    }),
    makeUpgrade('puer', 'tea', '普洱', '茶汤溅射，命中半径+20%', p => {
      p.inkRadiusMul += 0.2;
      p.damageMul += 0.1;
    }),
    makeUpgrade('baihao', 'tea', '白毫', '茶筅连射，攻速+15%', p => {
      p.attackInterval = Math.max(0.25, p.attackInterval * 0.85);
    }),

    // 手法：点茶三连 / 煎茶扇形 / 煮茶蓄力
    makeUpgrade('diancha', 'method', '点茶', '一瞬三发，弹幕+2', p => {
      p.multiShot += 2;
    }),
    makeUpgrade('jiancha', 'method', '煎茶', '扇形展开，散射角+20°', p => {
      p.fanAngle += 20;
    }),
    makeUpgrade('zhucha', 'method', '煮茶', '蓄力重注，伤害+25%', p => {
      p.damageMul += 0.25;
    }),

    // 心境：静 / 空灵墨 / 明
    makeUpgrade('jing', 'mind', '静', '心境澄明，攻速+10%', p => {
      p.attackInterval = Math.max(0.25, p.attackInterval * 0.9);
    }),
    makeUpgrade('kongling', 'mind', '空灵墨', '灵墨充盈，暴击+8%', p => {
      p.critChance += 0.08;
    }),
    makeUpgrade('ming', 'mind', '明', '目明心亮，伤害+15%', p => {
      p.damageMul += 0.15;
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

export function pickThree(levels: Record<string, number>): Upgrade[] {
  const pool = buildUpgradePool(levels);
  // 优先出没满级的，打乱
  const available = pool
    .filter(u => (levels[u.id] ?? 0) < u.maxLevel)
    .sort(() => Math.random() - 0.5)
    .slice(0, 3);
  return available;
}
