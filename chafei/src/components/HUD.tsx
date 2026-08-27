import React from 'react';
import { View, StyleSheet, Text } from 'react-native';
import { COLORS } from '../game/config';

interface Props {
  wallHp: number;
  wallMaxHp: number;
  score: number;
  timeLeft: number;
  level: number;
  exp: number;
  expCap: number;
  maxLevel: number;
  wave: number;
  totalWaves: number;
  kills: number;
}

function fmtTime(totalSeconds: number) {
  const s = Math.max(0, Math.floor(totalSeconds));
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return `${m}:${sec.toString().padStart(2, '0')}`;
}

export function HUD({ wallHp, wallMaxHp, score, timeLeft, level, exp, expCap, maxLevel, wave, totalWaves, kills }: Props) {
  const hpPct = Math.max(0, wallHp / wallMaxHp);
  const expPct = level >= maxLevel ? 1 : Math.max(0, Math.min(1, exp / expCap));
  const isMaxLevel = level >= maxLevel;
  const hpColor = hpPct > 0.5 ? COLORS.green : hpPct > 0.25 ? COLORS.orange : COLORS.red;

  return (
    <View style={styles.container} pointerEvents="none">
      {/* 顶部：波次 + 计时 + 分数 */}
      <View style={styles.topRow}>
        <View style={styles.waveBadge}>
          <Text style={styles.waveText}>{wave}/{totalWaves}</Text>
        </View>
        <Text style={styles.timer}>{fmtTime(timeLeft)}</Text>
        <Text style={styles.score}>{score}</Text>
      </View>

      {/* 等级徽章 */}
      <View style={styles.levelRow}>
        <View style={styles.levelBadge}>
          <Text style={styles.levelText}>Lv.{level}{isMaxLevel ? ' MAX' : ''}</Text>
        </View>
        <Text style={styles.killsText}>击杀 {kills}</Text>
      </View>

      {/* 城墙血条 */}
      <View style={styles.barRow}>
        <Text style={styles.label}>城墙</Text>
        <View style={[styles.bar, { width: 180 }]}>
          <View style={[styles.fill, { width: `${hpPct * 100}%`, backgroundColor: hpColor }]} />
        </View>
        <Text style={styles.hpNum}>{Math.ceil(wallHp)}</Text>
      </View>

      {/* 经验条 */}
      <View style={styles.barRow}>
        <Text style={styles.label}>{isMaxLevel ? '圆满' : '修为'}</Text>
        <View style={[styles.bar, { width: 140 }]}>
          <View style={[styles.fill, { width: `${expPct * 100}%`, backgroundColor: COLORS.blue }]} />
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 44,
    left: 0,
    right: 0,
    paddingHorizontal: 16,
  },
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  waveBadge: {
    backgroundColor: COLORS.pencil,
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderRadius: 10,
  },
  waveText: {
    fontSize: 14,
    color: COLORS.paper,
    fontWeight: 'bold',
  },
  timer: {
    fontSize: 22,
    color: COLORS.pencil,
    fontWeight: 'bold',
  },
  score: {
    fontSize: 18,
    color: COLORS.pencilLight,
    fontWeight: '600',
  },
  levelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 6,
    marginBottom: 4,
  },
  levelBadge: {
    backgroundColor: 'rgba(74,144,217,0.15)',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(74,144,217,0.4)',
  },
  levelText: {
    fontSize: 12,
    color: COLORS.blue,
    fontWeight: 'bold',
  },
  killsText: {
    fontSize: 12,
    color: COLORS.pencilLight,
    marginLeft: 10,
  },
  barRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 5,
  },
  label: {
    width: 36,
    fontSize: 12,
    color: COLORS.pencilLight,
    marginRight: 6,
  },
  bar: {
    height: 9,
    backgroundColor: 'rgba(44,44,44,0.08)',
    borderRadius: 5,
    overflow: 'hidden',
  },
  fill: {
    height: '100%',
    borderRadius: 5,
  },
  hpNum: {
    fontSize: 11,
    color: COLORS.pencilLight,
    marginLeft: 6,
    minWidth: 40,
  },
});
