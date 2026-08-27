import React, { useEffect, useRef, useState } from 'react';
import {
  SafeAreaView,
  StyleSheet,
  View,
  Text,
  TouchableOpacity,
  useWindowDimensions,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import {
  clampInk,
  makePlayer,
  resetId,
  spawnEnemies,
  updateEnemies,
  updatePlayer,
} from './game/engine';
import { GAME } from './game/config';
import type { Enemy, Player, Projectile, Upgrade } from './game/types';
import { pickThree } from './game/upgrades';
import { GameCanvas } from './components/GameCanvas';
import { HUD } from './components/HUD';
import { UpgradeCards } from './components/UpgradeCards';

type GameStatus = 'menu' | 'playing' | 'upgrade' | 'won' | 'lost';

interface GameSnapshot {
  status: GameStatus;
  player: Player;
  enemies: Enemy[];
  projectiles: Projectile[];
  ink: number;
  score: number;
  timeLeft: number;
  elapsed: number;
  spawnTimer: number;
  upgradeLevels: Record<string, number>;
  upgradeOptions: Upgrade[];
}

export default function App() {
  const { width, height } = useWindowDimensions();
  const [frame, setFrame] = useState(0);
  const game = useRef<GameSnapshot>({
    status: 'menu',
    player: makePlayer(),
    enemies: [],
    projectiles: [],
    ink: 0,
    score: 0,
    timeLeft: GAME.duration,
    elapsed: 0,
    spawnTimer: 0,
    upgradeLevels: {},
    upgradeOptions: [],
  });

  function startGame() {
    resetId();
    game.current = {
      status: 'playing',
      player: makePlayer(),
      enemies: [],
      projectiles: [],
      ink: 0,
      score: 0,
      timeLeft: GAME.duration,
      elapsed: 0,
      spawnTimer: 0,
      upgradeLevels: {},
      upgradeOptions: [],
    };
    setFrame(f => f + 1);
  }

  function pickUpgrade(u: Upgrade) {
    const g = game.current;
    u.effect(g.player);
    g.upgradeLevels[u.id] = (g.upgradeLevels[u.id] ?? 0) + 1;
    g.ink = Math.max(0, g.ink - GAME.inkToLevel);
    g.status = 'playing';
  }

  useEffect(() => {
    let last = Date.now();
    let raf = 0;
    const loop = (now: number) => {
      const dt = Math.min((now - last) / 1000, 0.05);
      last = now;
      const g = game.current;

      if (g.status === 'playing') {
        g.elapsed += dt;
        g.timeLeft = Math.max(0, GAME.duration - g.elapsed);

        if (g.timeLeft <= 0) {
          g.status = 'won';
        } else {
          // spawn
          g.spawnTimer += dt;
          const difficulty = 1 + g.elapsed / 90;
          const interval = Math.max(0.35, GAME.spawnRateInitial / difficulty);
          while (g.spawnTimer >= interval) {
            g.spawnTimer -= interval;
            g.enemies.push(...spawnEnemies(g.timeLeft, g.elapsed, interval));
          }

          // player auto attack
          updatePlayer(g.player, dt, g.enemies, g.projectiles);

          // projectiles hit enemies
          for (let i = g.projectiles.length - 1; i >= 0; i--) {
            const p = g.projectiles[i];
            p.pos.x += p.vel.x * dt;
            p.pos.y += p.vel.y * dt;
            p.life += dt;
            if (
              p.life > p.maxLife ||
              p.pos.y < -20 ||
              p.pos.x < -20 ||
              p.pos.x > GAME.width + 20
            ) {
              g.projectiles.splice(i, 1);
              continue;
            }
            for (const e of g.enemies) {
              if (e.dead) continue;
              const dx = p.pos.x - e.pos.x;
              const dy = p.pos.y - e.pos.y;
              const d2 = dx * dx + dy * dy;
              const r = e.radius + 6;
              if (d2 <= r * r) {
                let dmg = p.damage;
                if (Math.random() < g.player.critChance) {
                  dmg = Math.round(dmg * 1.5);
                }
                e.hp -= dmg;
                if (p.pierce <= 0) {
                  g.projectiles.splice(i, 1);
                  break;
                } else {
                  p.pierce -= 1;
                }
              }
            }
          }

          // enemies move & collide
          const result = updateEnemies(g.enemies, dt, g.player);
          g.player.hp -= result.damage;
          g.score += result.spawned.length;
          g.enemies.push(...result.spawned);

          // ink & level up
          g.ink = clampInk(g.ink + result.ink);
          g.score += Math.floor(result.ink / 2);

          if (g.player.hp <= 0) {
            g.status = 'lost';
          } else if (g.ink >= GAME.inkToLevel) {
            g.status = 'upgrade';
            g.upgradeOptions = pickThree(g.upgradeLevels);
          }
        }
      }

      setFrame(f => f + 1);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, []);

  const g = game.current;
  const scale = Math.min(
    (width || GAME.width) / GAME.width,
    (height || GAME.height) / GAME.height
  );

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="dark" />
      <View style={[styles.stage, { transform: [{ scale }] }]}>
        <GameCanvas player={g.player} enemies={g.enemies} projectiles={g.projectiles} />
        <HUD
          hp={g.player.hp}
          maxHp={g.player.maxHp}
          score={g.score}
          timeLeft={g.timeLeft}
          ink={g.ink}
          inkCap={GAME.inkToLevel}
        />

        {g.status === 'menu' && (
          <View style={styles.overlay}>
            <Text style={styles.title}>茶沸</Text>
            <Text style={styles.subtitle}>茶人静心 · 彩墨解压</Text>
            <TouchableOpacity style={styles.btn} onPress={startGame}>
              <Text style={styles.btnText}>起一炉清水</Text>
            </TouchableOpacity>
          </View>
        )}

        {g.status === 'upgrade' && (
          <UpgradeCards options={g.upgradeOptions} onPick={pickUpgrade} />
        )}

        {(g.status === 'won' || g.status === 'lost') && (
          <View style={styles.overlay}>
            <Text style={styles.title}>{g.status === 'won' ? '茶成' : '壶沸心乱'}</Text>
            <Text style={styles.subtitle}>分数：{g.score}</Text>
            <TouchableOpacity style={styles.btn} onPress={startGame}>
              <Text style={styles.btnText}>再沏一壶</Text>
            </TouchableOpacity>
          </View>
        )}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#f3efe4',
  },
  stage: {
    width: GAME.width,
    height: GAME.height,
    alignSelf: 'center',
    backgroundColor: '#f3efe4',
  },
  overlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(243,239,228,0.96)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  title: {
    fontSize: 48,
    fontWeight: 'bold',
    color: '#1a1a1a',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 16,
    color: '#5f5e5a',
    marginBottom: 32,
  },
  btn: {
    backgroundColor: '#c0392b',
    paddingHorizontal: 32,
    paddingVertical: 14,
    borderRadius: 8,
  },
  btnText: {
    color: '#f7f3ea',
    fontSize: 18,
    fontWeight: 'bold',
  },
});
