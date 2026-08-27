import React from 'react';
import { View, StyleSheet, Text } from 'react-native';

interface Props {
  hp: number;
  maxHp: number;
  score: number;
  timeLeft: number;
  level: number;
  exp: number;
  expCap: number;
  maxLevel: number;
}

function fmtTime(totalSeconds: number) {
  const s = Math.max(0, Math.floor(totalSeconds));
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return `${m}:${sec.toString().padStart(2, '0')}`;
}

export function HUD({ hp, maxHp, score, timeLeft, level, exp, expCap, maxLevel }: Props) {
  const hpPct = Math.max(0, hp / maxHp);
  const expPct = level >= maxLevel ? 1 : Math.max(0, Math.min(1, exp / expCap));
  const isMaxLevel = level >= maxLevel;
  return (
    <View style={styles.container} pointerEvents="none">
      <View style={styles.topRow}>
        <Text style={styles.timer}>{fmtTime(timeLeft)}</Text>
        <View style={styles.levelBadge}>
          <Text style={styles.levelText}>Lv.{level}{isMaxLevel ? ' MAX' : ''}</Text>
        </View>
        <Text style={styles.score}>{score}</Text>
      </View>

      <View style={styles.barRow}>
        <Text style={styles.label}>心境</Text>
        <View style={[styles.bar, { width: 160 }]}>
          <View style={[styles.fill, { width: `${hpPct * 100}%`, backgroundColor: '#3b7a5c' }]} />
        </View>
      </View>

      <View style={styles.barRow}>
        <Text style={styles.label}>{isMaxLevel ? '圆满' : '修为'}</Text>
        <View style={[styles.bar, { width: 120 }]}>
          <View style={[styles.fill, { width: `${expPct * 100}%`, backgroundColor: '#b07a3c' }]} />
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 48,
    left: 0,
    right: 0,
    paddingHorizontal: 20,
  },
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  timer: {
    fontSize: 22,
    color: '#1a1a1a',
    fontWeight: 'bold',
  },
  levelBadge: {
    backgroundColor: 'rgba(176,122,60,0.15)',
    paddingHorizontal: 10,
    paddingVertical: 2,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(176,122,60,0.4)',
  },
  levelText: {
    fontSize: 13,
    color: '#b07a3c',
    fontWeight: 'bold',
  },
  score: {
    fontSize: 18,
    color: '#5f5e5a',
    fontWeight: '600',
  },
  barRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 8,
  },
  label: {
    width: 36,
    fontSize: 13,
    color: '#5f5e5a',
    marginRight: 8,
  },
  bar: {
    height: 10,
    backgroundColor: 'rgba(26,26,26,0.08)',
    borderRadius: 5,
    overflow: 'hidden',
  },
  fill: {
    height: '100%',
    borderRadius: 5,
  },
});
