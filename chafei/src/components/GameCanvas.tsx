import React from 'react';
import { StyleSheet } from 'react-native';
import {
  Canvas,
  Circle,
  Group,
  Path,
  Rect,
  Skia,
  vec,
} from '@shopify/react-native-skia';
import { GAME, COLORS } from '../game/config';
import type { Enemy, Player, Projectile } from '../game/types';

interface Props {
  player: Player;
  enemies: Enemy[];
  projectiles: Projectile[];
}

function enemyPath(type: Enemy['type'], r: number) {
  const path = Skia.Path.Make();
  if (type === 'foam') {
    // 浮沫：三瓣圆泡
    path.addCircle(0, -r * 0.5, r * 0.55);
    path.addCircle(-r * 0.5, r * 0.3, r * 0.45);
    path.addCircle(r * 0.5, r * 0.3, r * 0.45);
  } else if (type === 'scorch') {
    // 焦苦：锯齿火焰
    const points = 5;
    for (let i = 0; i <= points * 2; i++) {
      const a = (i / (points * 2)) * Math.PI * 2 - Math.PI / 2;
      const radius = i % 2 === 0 ? r : r * 0.55;
      const x = Math.cos(a) * radius;
      const y = Math.sin(a) * radius;
      if (i === 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    path.close();
  } else {
    // 杂念：不规则墨团
    path.addCircle(0, 0, r);
    path.addCircle(-r * 0.45, -r * 0.2, r * 0.5);
    path.addCircle(r * 0.35, r * 0.35, r * 0.45);
  }
  return path;
}

function projectilePath() {
  const path = Skia.Path.Make();
  // 水滴形
  path.moveTo(0, -6);
  path.cubicTo(5, -2, 5, 5, 0, 6);
  path.cubicTo(-5, 5, -5, -2, 0, -6);
  path.close();
  return path;
}

export function GameCanvas({ player, enemies, projectiles }: Props) {
  return (
    <Canvas style={styles.canvas}>
      {/* 宣纸底色 */}
      <Rect x={0} y={0} width={GAME.width} height={GAME.height} color={COLORS.paper} />

      {/* 淡墨晕染背景 */}
      <Group opacity={0.18}>
        <Circle cx={60} cy={180} r={120} color={COLORS.inkGray} />
        <Circle cx={330} cy={620} r={160} color={COLORS.inkGray} />
        <Circle cx={200} cy={380} r={90} color={COLORS.inkGray} />
      </Group>

      {/* 玩家：茶筅 */}
      <Group transform={[{ translate: [player.pos.x, player.pos.y] }]}>
        {/* 茶人底座 */}
        <Path
          path={(() => {
            const p = Skia.Path.Make();
            p.moveTo(-24, 20);
            p.lineTo(-18, 42);
            p.moveTo(0, 18);
            p.lineTo(0, 45);
            p.moveTo(24, 20);
            p.lineTo(18, 42);
            return p;
          })()}
          strokeWidth={3}
          style="stroke"
          color={COLORS.ink}
          opacity={0.8}
        />
        {/* 朱砂腰带 */}
        <Rect x={-22} y={24} width={44} height={5} color={COLORS.cinnabar} />
        {/* 茶筅放射线 */}
        {Array.from({ length: 9 }).map((_, i) => {
          const a = ((i / 9) * Math.PI * 2) - Math.PI / 2;
          const r = player.radius * 0.9;
          const x = Math.cos(a) * r;
          const y = Math.sin(a) * r;
          return (
            <Path
              key={i}
              path={(() => {
                const p = Skia.Path.Make();
                p.moveTo(0, 0);
                p.lineTo(x, y);
                return p;
              })()}
              strokeWidth={2.5}
              style="stroke"
              color={i % 2 === 0 ? COLORS.teal : COLORS.ink}
            />
          );
        })}
      </Group>

      {/* 水线弹幕 */}
      {projectiles.map(p => {
        const angle = Math.atan2(p.vel.y, p.vel.x) + Math.PI / 2;
        return (
          <Group
            key={p.id}
            transform={[
              { translate: [p.pos.x, p.pos.y] },
              { rotate: angle },
            ]}
          >
            <Path
              path={projectilePath()}
              color={COLORS.teal}
              opacity={Math.max(0, 1 - p.life / p.maxLife)}
            />
          </Group>
        );
      })}

      {/* 敌人 */}
      {enemies.map(e => (
        <Group key={e.id} transform={[{ translate: [e.pos.x, e.pos.y] }]}>
          <Path path={enemyPath(e.type, e.radius)} color={e.color} opacity={0.92} />
          {/* 血条 */}
          <Rect
            x={-e.radius}
            y={-e.radius - 8}
            width={e.radius * 2}
            height={3}
            color={COLORS.inkGray}
          />
          <Rect
            x={-e.radius}
            y={-e.radius - 8}
            width={e.radius * 2 * Math.max(0, e.hp / e.maxHp)}
            height={3}
            color={COLORS.cinnabar}
          />
        </Group>
      ))}
    </Canvas>
  );
}

const styles = StyleSheet.create({
  canvas: {
    width: GAME.width,
    height: GAME.height,
  },
});
