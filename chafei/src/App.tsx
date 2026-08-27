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
  currentWave,
  makePlayer,
  resetId,
  spawnEnemies,
  updateEnemies,
  updatePlayer,
} from './game/engine';
import { GAME, LEVEL, WAVES, COLORS } from './game/config';
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
  wallHp: number;
  score: number;
  kills: number;
  timeLeft: number;
  elapsed: number;
  spawnTimer: number;
  upgradeLevels: Record<string, number>;
  upgradeOptions: Upgrade[];
  lastCritAt: number;
  pendingLevelUps: number;
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
    wallHp: GAME.wallMaxHp,
    score: 0,
    kills: 0,
    timeLeft: GAME.duration,
    elapsed: 0,
    spawnTimer: 0,
    upgradeLevels: {},
    upgradeOptions: [],
    lastCritAt: -10,
    pendingLevelUps: 0,
  });

  useEffect(() => {
    AsyncStorage.getItem('papermage_high_score').then(v => {
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
      wallHp: GAME.wallMaxHp,
      score: 0,
      kills: 0,
      timeLeft: GAME.duration,
      elapsed: 0,
      spawnTimer: 0,
      upgradeLevels: {},
      upgradeOptions: [],
      lastCritAt: -10,
      pendingLevelUps: 0,
    };
    setFrame(f => f + 1);
  }

  function togglePause() {
    const g = game.current;
    if (g.status === 'playing') g.status = 'paused';
    else if (g.status === 'paused') g.status = 'playing';
    setFrame(f => f + 1);
  }

  function saveHighScore(score: number) {
    if (score > highScore) {
      setHighScore(score);
      AsyncStorage.setItem('papermage_high_score', String(score)).catch(() => {});
    }
  }

  function pickUpgrade(u: Upgrade) {
    const g = game.current;
    // 修复城墙：在 App 层处理（不修改 player）
    if (u.id === 'repair') {
      g.wallHp = Math.min(GAME.wallMaxHp, g.wallHp + 500);
    } else {
      u.effect(g.player);
    }
    g.upgradeLevels[u.id] = (g.upgradeLevels[u.id] ?? 0) + 1;
    if (g.pendingLevelUps > 0) {
      g.pendingLevelUps--;
      g.upgradeOptions = pickThree(g.upgradeLevels, g.player);
    } else {
      g.status = 'playing';
    }
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
        const wave = currentWave(g.elapsed);

        if (g.timeLeft <= 0) {
          g.status = 'won';
          saveHighScore(g.score);
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
        } else {
          // 出怪：波次越高间隔越短
          g.spawnTimer += dt;
          const waveProgress = (wave - 1) / WAVES.total;
          const interval = Math.max(0.4, GAME.spawnRateInitial - waveProgress * 1.4);
          while (g.spawnTimer >= interval) {
            g.spawnTimer -= interval;
            g.enemies.push(...spawnEnemies(g.elapsed, wave));
          }

          // 玩家自动攻击（奥术飞弹+冰锥+滚木）
          updatePlayer(g.player, dt, g.enemies, g.projectiles);

          // 弹道命中
          for (let i = g.projectiles.length - 1; i >= 0; i--) {
            const p = g.projectiles[i];
            p.pos.x += p.vel.x * dt;
            p.pos.y += p.vel.y * dt;
            p.life += dt;
            if (
              p.life > p.maxLife ||
              p.pos.y < -40 ||
              p.pos.x < -60 ||
              p.pos.x > GAME.width + 60
            ) {
              g.projectiles.splice(i, 1);
              continue;
            }
            // 滚木宽度命中
            const hitRadius = p.kind === 'log' ? 45 : 8;
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

          // 敌人移动 & 撞城墙
          const result = updateEnemies(g.enemies, dt, g.player);
          if (result.damage > 0) {
            g.wallHp -= result.damage;
            Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
          }
          g.enemies.push(...result.spawned);

          // 经验 & 等级
          if (result.exp > 0) {
            g.player.exp += result.exp;
            g.score += result.exp * 10;
            g.kills += 1;
            let leveledUp = false;
            while (
              g.player.level < LEVEL.maxLevel &&
              g.player.exp >= LEVEL.expForLevel(g.player.level)
            ) {
              g.player.exp -= LEVEL.expForLevel(g.player.level);
              g.player.level++;
              leveledUp = true;
              g.pendingLevelUps++;
            }
            if (g.player.level >= LEVEL.maxLevel) {
              g.player.exp = 0;
            }
            if (leveledUp) {
              g.pendingLevelUps--;
              g.status = 'upgrade';
              g.upgradeOptions = pickThree(g.upgradeLevels, g.player);
              Haptics.selectionAsync();
            }
          }

          if (g.wallHp <= 0) {
            g.wallHp = 0;
            g.status = 'lost';
            saveHighScore(g.score);
            Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
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
  const wave = currentWave(g.elapsed);
  const showCrit = g.elapsed - g.lastCritAt < 0.6;

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="dark" />
      <View style={[styles.stage, { transform: [{ scale }] }]}>
        <GameCanvas
          player={g.player}
          enemies={g.enemies}
          projectiles={g.projectiles}
          elapsed={g.elapsed}
        />
        <HUD
          wallHp={g.wallHp}
          wallMaxHp={GAME.wallMaxHp}
          score={g.score}
          timeLeft={g.timeLeft}
          level={g.player.level}
          exp={g.player.exp}
          expCap={g.player.level < LEVEL.maxLevel ? LEVEL.expForLevel(g.player.level) : 1}
          maxLevel={LEVEL.maxLevel}
          wave={wave}
          totalWaves={WAVES.total}
          kills={g.kills}
        />

        {showCrit && (
          <View style={styles.critBadge} pointerEvents="none">
            <Text style={styles.critText}>暴击!</Text>
          </View>
        )}

        {(g.status === 'playing' || g.status === 'paused') && (
          <TouchableOpacity style={styles.pauseBtn} onPress={togglePause}>
            <Text style={styles.pauseText}>{g.status === 'paused' ? '▶' : '❚❚'}</Text>
          </TouchableOpacity>
        )}

        {g.status === 'menu' && (
          <View style={styles.overlay}>
            <Text style={styles.title}>纸上法师</Text>
            <Text style={styles.subtitle}>见习守塔法师「小白」· 铅笔涂鸦风</Text>
            {highScore > 0 && (
              <Text style={styles.highScore}>最高分：{highScore}</Text>
            )}
            <TouchableOpacity style={styles.btn} onPress={startGame}>
              <Text style={styles.btnText}>开始守塔</Text>
            </TouchableOpacity>
          </View>
        )}

        {g.status === 'paused' && (
          <View style={styles.overlay}>
            <Text style={styles.title}>暂停</Text>
            <Text style={styles.subtitle}>第 {wave} 波 · 分数：{g.score}</Text>
            <TouchableOpacity style={styles.btn} onPress={togglePause}>
              <Text style={styles.btnText}>继续</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[styles.btn, styles.btnSecondary]} onPress={startGame}>
              <Text style={styles.btnText}>重新开始</Text>
            </TouchableOpacity>
          </View>
        )}

        {g.status === 'upgrade' && (
          <UpgradeCards options={g.upgradeOptions} onPick={pickUpgrade} />
        )}

        {(g.status === 'won' || g.status === 'lost') && (
          <View style={styles.overlay}>
            <Text style={styles.title}>{g.status === 'won' ? '守塔成功' : '城墙告破'}</Text>
            <Text style={styles.subtitle}>分数：{g.score} · 击杀：{g.kills}</Text>
            {g.score >= highScore && g.score > 0 && (
              <Text style={styles.newRecord}>新纪录!</Text>
            )}
            <Text style={styles.highScore}>最高分：{highScore}</Text>
            <TouchableOpacity style={styles.btn} onPress={startGame}>
              <Text style={styles.btnText}>再来一局</Text>
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
    backgroundColor: COLORS.paper,
  },
  stage: {
    width: GAME.width,
    height: GAME.height,
    alignSelf: 'center',
    backgroundColor: COLORS.paper,
  },
  overlay: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(242,239,233,0.96)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  title: {
    fontSize: 44,
    fontWeight: 'bold',
    color: COLORS.pencil,
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 15,
    color: COLORS.pencilLight,
    marginBottom: 16,
  },
  highScore: {
    fontSize: 14,
    color: COLORS.pencilLight,
    marginBottom: 24,
  },
  newRecord: {
    fontSize: 20,
    color: COLORS.orange,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  btn: {
    backgroundColor: COLORS.pencil,
    paddingHorizontal: 36,
    paddingVertical: 14,
    borderRadius: 8,
    marginBottom: 12,
  },
  btnSecondary: {
    backgroundColor: COLORS.pencilLight,
  },
  btnText: {
    color: COLORS.paper,
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
    backgroundColor: 'rgba(44,44,44,0.08)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  pauseText: {
    fontSize: 14,
    color: COLORS.pencil,
    fontWeight: 'bold',
  },
  critBadge: {
    position: 'absolute',
    top: 90,
    alignSelf: 'center',
    backgroundColor: COLORS.orange,
    paddingHorizontal: 16,
    paddingVertical: 4,
    borderRadius: 12,
  },
  critText: {
    color: COLORS.paper,
    fontSize: 16,
    fontWeight: 'bold',
  },
});
