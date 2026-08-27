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
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Haptics from 'expo-haptics';
import {
  clampInk,
  difficultyAt,
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

type GameStatus = 'menu' | 'playing' | 'paused' | 'upgrade' | 'won' | 'lost';

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
  lastCritAt: number; // 最近一次暴击的 elapsed 时间，用于视觉反馈
}

export default function App() {
  const { width, height } = useWindowDimensions();
  const [frame, setFrame] = useState(0);
  const [highScore, setHighScore] = useState(0);
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
    lastCritAt: -10,
  });

  // 启动时读取本地最高分
  useEffect(() => {
    AsyncStorage.getItem('chafei_high_score').then(v => {
      if (v) setHighScore(parseInt(v, 10) || 0);
    }).catch(() => {});
  }, []);

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
      lastCritAt: -10,
    };
    setFrame(f => f + 1);
  }

  function togglePause() {
    const g = game.current;
    if (g.status === 'playing') {
      g.status = 'paused';
    } else if (g.status === 'paused') {
      g.status = 'playing';
    }
    setFrame(f => f + 1);
  }

  function saveHighScore(score: number) {
    if (score > highScore) {
      setHighScore(score);
      AsyncStorage.setItem('chafei_high_score', String(score)).catch(() => {});
    }
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
          saveHighScore(g.score);
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
        } else {
          // spawn —— 节奏由 interval 控制，每 tick 生成 1 只
          g.spawnTimer += dt;
          const difficulty = difficultyAt(g.elapsed);
          const interval = Math.max(0.35, GAME.spawnRateInitial / difficulty);
          while (g.spawnTimer >= interval) {
            g.spawnTimer -= interval;
            g.enemies.push(...spawnEnemies(g.elapsed));
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
            // 普洱溅射：命中半径随 inkRadiusMul 放大
            const hitRadius = 6 * g.player.inkRadiusMul;
            for (const e of g.enemies) {
              if (e.dead) continue;
              const dx = p.pos.x - e.pos.x;
              const dy = p.pos.y - e.pos.y;
              const d2 = dx * dx + dy * dy;
              const r = e.radius + hitRadius;
              if (d2 <= r * r) {
                let dmg = p.damage;
                const isCrit = Math.random() < g.player.critChance;
                if (isCrit) {
                  dmg = Math.round(dmg * 1.5);
                  g.lastCritAt = g.elapsed;
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
          if (result.damage > 0) {
            Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
          }
          // 分裂出的小怪不计分（只在击杀时通过 ink 计分）
          g.enemies.push(...result.spawned);

          // ink & level up —— 击杀灵墨折算分数
          g.ink = clampInk(g.ink + result.ink);
          g.score += Math.floor(result.ink / 2);

          if (g.player.hp <= 0) {
            g.status = 'lost';
            saveHighScore(g.score);
            Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
          } else if (g.ink >= GAME.inkToLevel) {
            g.status = 'upgrade';
            g.upgradeOptions = pickThree(g.upgradeLevels);
            Haptics.selectionAsync();
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

  const showCrit = g.elapsed - g.lastCritAt < 0.6;

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

        {/* 暴击反馈 */}
        {showCrit && (
          <View style={styles.critBadge} pointerEvents="none">
            <Text style={styles.critText}>暴击!</Text>
          </View>
        )}

        {/* 暂停按钮（游戏中） */}
        {(g.status === 'playing' || g.status === 'paused') && (
          <TouchableOpacity style={styles.pauseBtn} onPress={togglePause}>
            <Text style={styles.pauseText}>{g.status === 'paused' ? '▶' : '❚❚'}</Text>
          </TouchableOpacity>
        )}

        {g.status === 'menu' && (
          <View style={styles.overlay}>
            <Text style={styles.title}>茶沸</Text>
            <Text style={styles.subtitle}>茶人静心 · 彩墨解压</Text>
            {highScore > 0 && (
              <Text style={styles.highScore}>最高分：{highScore}</Text>
            )}
            <TouchableOpacity style={styles.btn} onPress={startGame}>
              <Text style={styles.btnText}>起一炉清水</Text>
            </TouchableOpacity>
          </View>
        )}

        {g.status === 'paused' && (
          <View style={styles.overlay}>
            <Text style={styles.title}>暂歇</Text>
            <Text style={styles.subtitle}>当前分数：{g.score}</Text>
            <TouchableOpacity style={styles.btn} onPress={togglePause}>
              <Text style={styles.btnText}>继续煮茶</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[styles.btn, styles.btnSecondary]} onPress={startGame}>
              <Text style={styles.btnText}>重沏一壶</Text>
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
            {g.score >= highScore && g.score > 0 && (
              <Text style={styles.newRecord}>新纪录!</Text>
            )}
            <Text style={styles.highScore}>最高分：{highScore}</Text>
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
    marginBottom: 16,
  },
  highScore: {
    fontSize: 14,
    color: '#5f5e5a',
    marginBottom: 24,
  },
  newRecord: {
    fontSize: 20,
    color: '#c0392b',
    fontWeight: 'bold',
    marginBottom: 8,
  },
  btn: {
    backgroundColor: '#c0392b',
    paddingHorizontal: 32,
    paddingVertical: 14,
    borderRadius: 8,
    marginBottom: 12,
  },
  btnSecondary: {
    backgroundColor: '#5f5e5a',
  },
  btnText: {
    color: '#f7f3ea',
    fontSize: 18,
    fontWeight: 'bold',
  },
  pauseBtn: {
    position: 'absolute',
    top: 48,
    right: 16,
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(26,26,26,0.08)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  pauseText: {
    fontSize: 14,
    color: '#1a1a1a',
    fontWeight: 'bold',
  },
  critBadge: {
    position: 'absolute',
    top: 90,
    alignSelf: 'center',
    backgroundColor: 'rgba(192,57,43,0.9)',
    paddingHorizontal: 16,
    paddingVertical: 4,
    borderRadius: 12,
  },
  critText: {
    color: '#f7f3ea',
    fontSize: 16,
    fontWeight: 'bold',
  },
});
