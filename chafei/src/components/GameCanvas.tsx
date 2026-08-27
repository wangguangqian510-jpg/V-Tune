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

// 茶叶剑气：柳叶形，两端尖，中间宽，带中脉
function teaLeafPath(size: number) {
  const path = Skia.Path.Make();
  const w = size * 0.35;
  const h = size;
  // 左半叶
  path.moveTo(0, -h);
  path.cubicTo(-w * 0.8, -h * 0.5, -w, h * 0.3, 0, h);
  // 右半叶
  path.cubicTo(w, h * 0.3, w * 0.8, -h * 0.5, 0, -h);
  path.close();
  return path;
}

// 茶人剑指角色
function TeaMaster({ player }: { player: Player }) {
  const p = player.pos;
  return (
    <Group transform={[{ translate: [p.x, p.y] }]}>
      {/* === 茶壶（左侧） === */}
      <Group transform={[{ translate: [-38, 18] }]}>
        {/* 壶身 */}
        <Circle cx={0} cy={0} r={12} color={COLORS.ink} opacity={0.85} />
        {/* 壶嘴 */}
        <Path
          path={(() => {
            const pp = Skia.Path.Make();
            pp.moveTo(10, -4);
            pp.lineTo(20, -8);
            pp.lineTo(18, -2);
            pp.close();
            return pp;
          })()}
          color={COLORS.ink}
          opacity={0.85}
        />
        {/* 壶盖钮 */}
        <Circle cx={0} cy={-11} r={3} color={COLORS.cinnabar} />
        {/* 蒸汽 */}
        <Path
          path={(() => {
            const pp = Skia.Path.Make();
            pp.moveTo(-3, -14);
            pp.cubicTo(-6, -20, 0, -22, -3, -28);
            return pp;
          })()}
          strokeWidth={1.5}
          style="stroke"
          color={COLORS.inkGray}
          opacity={0.4}
        />
        <Path
          path={(() => {
            const pp = Skia.Path.Make();
            pp.moveTo(3, -14);
            pp.cubicTo(6, -20, 0, -24, 3, -30);
            return pp;
          })()}
          strokeWidth={1.5}
          style="stroke"
          color={COLORS.inkGray}
          opacity={0.3}
        />
      </Group>

      {/* === 茶人身体 === */}
      {/* 下摆长袍（宽梯形） */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-22, 10);
          pp.lineTo(-30, 42);
          pp.lineTo(30, 42);
          pp.lineTo(22, 10);
          pp.close();
          return pp;
        })()}
        color={COLORS.ink}
        opacity={0.85}
      />
      {/* 长袍下摆纹路 */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-15, 20);
          pp.lineTo(-20, 42);
          pp.moveTo(0, 15);
          pp.lineTo(0, 42);
          pp.moveTo(15, 20);
          pp.lineTo(20, 42);
          return pp;
        })()}
        strokeWidth={1}
        style="stroke"
        color={COLORS.paperLight}
        opacity={0.3}
      />
      {/* 朱砂腰带 */}
      <Rect x={-24} y={8} width={48} height={5} color={COLORS.cinnabar} />
      {/* 上身（窄梯形） */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-14, -8);
          pp.lineTo(-18, 10);
          pp.lineTo(18, 10);
          pp.lineTo(14, -8);
          pp.close();
          return pp;
        })()}
        color={COLORS.ink}
        opacity={0.9}
      />

      {/* === 左臂（自然下垂） === */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-14, -4);
          pp.lineTo(-22, 14);
          return pp;
        })()}
        strokeWidth={5}
        style="stroke"
        strokeCap="round"
        color={COLORS.ink}
        opacity={0.9}
      />

      {/* === 右臂（抬起，剑指） === */}
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(12, -4);
          pp.lineTo(18, -22);
          return pp;
        })()}
        strokeWidth={5}
        style="stroke"
        strokeCap="round"
        color={COLORS.ink}
        opacity={0.9}
      />
      {/* 剑指手（两指向上） */}
      <Group transform={[{ translate: [18, -24] }]}>
        {/* 手掌 */}
        <Circle cx={0} cy={2} r={4} color={COLORS.ink} opacity={0.9} />
        {/* 食指（伸出） */}
        <Path
          path={(() => {
            const pp = Skia.Path.Make();
            pp.moveTo(-2, 0);
            pp.lineTo(-3, -12);
            return pp;
          })()}
          strokeWidth={2.5}
          style="stroke"
          strokeCap="round"
          color={COLORS.ink}
          opacity={0.9}
        />
        {/* 中指（伸出） */}
        <Path
          path={(() => {
            const pp = Skia.Path.Make();
            pp.moveTo(1, 0);
            pp.lineTo(2, -14);
            return pp;
          })()}
          strokeWidth={2.5}
          style="stroke"
          strokeCap="round"
          color={COLORS.ink}
          opacity={0.9}
        />
        {/* 指尖剑气微光 */}
        <Circle cx={-3} cy={-13} r={2} color={COLORS.tealLight} opacity={0.6} />
        <Circle cx={2} cy={-15} r={2} color={COLORS.tealLight} opacity={0.6} />
      </Group>

      {/* === 头部 === */}
      <Circle cx={0} cy={-16} r={9} color={COLORS.ink} opacity={0.9} />
      {/* 发髻 */}
      <Circle cx={0} cy={-25} r={4} color={COLORS.ink} opacity={0.9} />
      <Path
        path={(() => {
          const pp = Skia.Path.Make();
          pp.moveTo(-3, -27);
          pp.lineTo(0, -32);
          pp.lineTo(3, -27);
          return pp;
        })()}
        color={COLORS.cinnabar}
        opacity={0.8}
      />
      {/* 面部简化：两点眼 */}
      <Circle cx={-3} cy={-16} r={1} color={COLORS.paperLight} opacity={0.7} />
      <Circle cx={3} cy={-16} r={1} color={COLORS.paperLight} opacity={0.7} />
    </Group>
  );
}

export function GameCanvas({ player, enemies, projectiles }: Props) {
  return (
    <Canvas style={styles.canvas}>
      {/* 宣纸底色 */}
      <Rect x={0} y={0} width={GAME.width} height={GAME.height} color={COLORS.paper} />

      {/* 淡墨晕染背景 */}
      <Group opacity={0.12}>
        <Circle cx={80} cy={200} r={110} color={COLORS.inkGray} />
        <Circle cx={310} cy={580} r={140} color={COLORS.inkGray} />
        <Circle cx={195} cy={380} r={80} color={COLORS.inkGray} />
        <Circle cx={340} cy={150} r={60} color={COLORS.ochre} opacity={0.3} />
      </Group>

      {/* 敌人 */}
      {enemies.map(e => (
        <Group key={e.id} transform={[{ translate: [e.pos.x, e.pos.y] }]}>
          <Path path={enemyPath(e.type, e.radius)} color={e.color} opacity={0.92} />
          {/* 血条（仅非满血时显示） */}
          {e.hp < e.maxHp && (
            <>
              <Rect
                x={-e.radius}
                y={-e.radius - 8}
                width={e.radius * 2}
                height={3}
                color={COLORS.inkGray}
                opacity={0.5}
              />
              <Rect
                x={-e.radius}
                y={-e.radius - 8}
                width={e.radius * 2 * Math.max(0, e.hp / e.maxHp)}
                height={3}
                color={COLORS.cinnabar}
              />
            </>
          )}
        </Group>
      ))}

      {/* 茶叶剑气弹道 */}
      {projectiles.map(p => {
        const angle = Math.atan2(p.vel.y, p.vel.x) + Math.PI / 2;
        const fade = Math.max(0.3, 1 - p.life / p.maxLife);
        return (
          <Group
            key={p.id}
            transform={[
              { translate: [p.pos.x, p.pos.y] },
              { rotate: angle },
            ]}
          >
            {/* 剑气外光 */}
            <Path
              path={teaLeafPath(16)}
              color={COLORS.tealLight}
              opacity={fade * 0.3}
            />
            {/* 茶叶主体 */}
            <Path
              path={teaLeafPath(12)}
              color={COLORS.teal}
              opacity={fade}
            />
            {/* 中脉 */}
            <Path
              path={(() => {
                const pp = Skia.Path.Make();
                pp.moveTo(0, -10);
                pp.lineTo(0, 10);
                return pp;
              })()}
              strokeWidth={1}
              style="stroke"
              color={COLORS.paperLight}
              opacity={fade * 0.6}
            />
          </Group>
        );
      })}

      {/* 茶人剑指（玩家） */}
      <TeaMaster player={player} />
    </Canvas>
  );
}

const styles = StyleSheet.create({
  canvas: {
    width: GAME.width,
    height: GAME.height,
  },
});
