import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import type { Upgrade } from '../game/types';
import { UPGRADE_TITLES } from '../game/upgrades';

interface Props {
  options: Upgrade[];
  onPick: (u: Upgrade) => void;
}

export function UpgradeCards({ options, onPick }: Props) {
  return (
    <View style={styles.overlay}>
      <View style={styles.panel}>
        <Text style={styles.title}>灵墨充盈，择一精进</Text>
        <View style={styles.cards}>
          {options.map(u => (
            <TouchableOpacity
              key={u.id}
              activeOpacity={0.8}
              onPress={() => onPick(u)}
              style={styles.card}
            >
              <Text style={styles.category}>{UPGRADE_TITLES[u.category]}</Text>
              <Text style={styles.name}>{u.name}</Text>
              <Text style={styles.desc}>{u.desc}</Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  overlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(243,239,228,0.92)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  panel: {
    width: '90%',
    alignItems: 'center',
  },
  title: {
    fontSize: 22,
    color: '#1a1a1a',
    fontWeight: 'bold',
    marginBottom: 24,
  },
  cards: {
    flexDirection: 'column',
    width: '100%',
    gap: 12,
  },
  card: {
    backgroundColor: '#f7f3ea',
    borderWidth: 1.5,
    borderColor: '#c0392b',
    borderRadius: 12,
    padding: 18,
  },
  category: {
    fontSize: 12,
    color: '#c0392b',
    fontWeight: '700',
    marginBottom: 4,
  },
  name: {
    fontSize: 18,
    color: '#1a1a1a',
    fontWeight: 'bold',
    marginBottom: 6,
  },
  desc: {
    fontSize: 14,
    color: '#5f5e5a',
    lineHeight: 20,
  },
});
