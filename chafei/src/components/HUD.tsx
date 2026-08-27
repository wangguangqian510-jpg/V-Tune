import React from 'react';
import { View, StyleSheet, Text } from 'react-native';

interface Props {
  hp: number;
  maxHp: number;
  score: number;
  timeLeft: number;
  ink: number;
  inkCap: number;
}

function fmtTime(totalSeconds: number) {
  const s = Math.max(0, Math.floor(totalSeconds));
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return `${m}:${sec.toString().padStart(2, '0')}`;
}

export function HUD({ hp, maxHp, score, timeLeft, ink, inkCap }: Props) {
  const hpPct = Math.max(0, hp / maxHp);
  const inkPct = Math.max(0, Math.min(1, ink / inkCap));
  return (
    <View style={styles.container} pointerEvents="none">
      <View style={styles.topRow}>
        <Text style={styles.timer}>{fmtTime(timeLeft)}</Text>
        <Text style={styles.score}>{score}</Text>
      </View>

      <View style={styles.barRow}>
        <Text style={styles.label}>心境</Text>
        <View style={[styles.bar, { width: 160 }]}>
          <View style={[styles.fill, { width: `${hpPct * 100}%`, backgroundColor: '#3b7a5c' }]} />
        </View>
      </View>

      <View style={styles.barRow}>
        <Text style={styles.label}>灵墨</Text>
        <View style={[styles.bar, { width: 120 }]}>
          <View style={[styles.fill, { width: `${inkPct * 100}%`, backgroundColor: '#c0392b' }]} />
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
