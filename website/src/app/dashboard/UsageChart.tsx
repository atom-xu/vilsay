"use client";

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";

type Pt = { date: string; count: number };

export function UsageChart({ data }: { data: Pt[] }) {
  return (
    <ResponsiveContainer width="100%" height="100%">
      <LineChart data={data}>
        <CartesianGrid strokeDasharray="3 3" />
        <XAxis dataKey="date" hide />
        <YAxis />
        <Tooltip />
        <Line type="monotone" dataKey="count" stroke="#007AFF" strokeWidth={2} />
      </LineChart>
    </ResponsiveContainer>
  );
}
