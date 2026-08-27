// 《纸上法师》配置 —— 铅笔手绘涂鸦风，守门型 Roguelike 割草
// 世界层 100% 灰阶，UI/特效层高饱和点缀

export const COLORS = {
  // 纸张底色
  paper: '#F2EFE9',
  paperDark: '#E8E4DA',
  // 铅笔线条（不用纯黑，用深灰更像铅笔）
  pencil: '#2C2C2C',
  pencilLight: '#6B6B6B',
  pencilFaint: '#A0A0A0',
  // UI 高饱和点缀色
  orange: '#F5A623',
  blue: '#4A90D9',
  green: '#7ED321',
  red: '#D0021B',
  // 墨团精英
  inkBlack: '#1A1A1A',
  // 奥术飞弹
  arcane: '#6B5B95',
  arcaneLight: '#9B8BC5',
};

export const GAME = {
  width: 390,
  height: 844,
  duration: 240, // 4 分钟（20 波 × 12 秒）
  wallMaxHp: 3100, // 城墙血量（唯一失败条件）
  playerX: 195,
  playerY: 700, // 站在涟漪石台上
  playerRadius: 30,
  // 初始技能：奥术飞弹 Lv.1
  attackInterval: 1.0, // 冷却 1 秒
  projectileSpeed: 420,
  projectileDamage: 20,
  maxProjectiles: 40,
  spawnRateInitial: 2.0, // 初始出怪间隔
  // 城墙判定线（敌人越过此线扣血）
  wallLineY: 760,
};

// 等级经验曲线（来自报告 6.4）
// L1→2:5  L2→3:10  L3→4:15  L4→5:22  L5→6:30  L6→7:39  L7→8:49  L8→9:61  L9→10:74
export const LEVEL = {
  maxLevel: 10,
  expForLevel: (level: number) => {
    const table = [0, 5, 10, 15, 22, 30, 39, 49, 61, 74];
    return table[Math.min(level, 9)] || 100;
  },
};

// 波次系统：20 波，每波 12 秒
export const WAVES = {
  total: 20,
  durationPerWave: 12, // 秒
  // 怪物随波缩放：系数 = 1 + (波次-1)×0.12（第20波≈3.3倍）
  hpScale: (wave: number) => 1 + (wave - 1) * 0.12,
  damageScale: (wave: number) => 1 + (wave - 1) * 0.12,
  // 精英波
  eliteWaves: [10, 20],
};

export type EnemyType = 'imp' | 'cloud' | 'twin' | 'ink_elite';

export interface EnemyDef {
  type: EnemyType;
  name: string;
  hp: number;
  speed: number;
  radius: number;
  damage: number; // 撞墙伤害
  exp: number;
  color: string;
  // 特殊行为
  sleepDuration?: number; // 飘云怪：前N秒睡觉不动
  isTwin?: boolean; // 双子面
  isElite?: boolean; // 墨团精英
}

export const ENEMIES: Record<EnemyType, EnemyDef> = {
  imp: {
    type: 'imp',
    name: '小鬼面',
    hp: 30,
    speed: 60,
    radius: 16,
    damage: 50,
    exp: 1,
    color: COLORS.pencil,
  },
  cloud: {
    type: 'cloud',
    name: '飘云怪',
    hp: 60,
    speed: 40,
    radius: 22,
    damage: 80,
    exp: 2,
    color: COLORS.pencilLight,
    sleepDuration: 3, // 前3秒睡觉
  },
  twin: {
    type: 'twin',
    name: '双子面',
    hp: 45,
    speed: 75,
    radius: 14,
    damage: 60,
    exp: 2,
    color: COLORS.pencil,
    isTwin: true,
  },
  ink_elite: {
    type: 'ink_elite',
    name: '墨团精英',
    hp: 600,
    speed: 50,
    radius: 36, // 体积×2
    damage: 400,
    exp: 20,
    color: COLORS.inkBlack,
    isElite: true,
  },
};
