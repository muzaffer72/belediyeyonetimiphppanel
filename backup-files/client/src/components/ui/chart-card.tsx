import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useTranslation } from "@/lib/i18n";
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, Legend } from "recharts";
import { BarChart, Bar, XAxis, YAxis, CartesianGrid } from "recharts";
import { LineChart, Line } from "recharts";

interface ChartCardProps {
  title: string;
  children: React.ReactNode;
  action?: React.ReactNode;
}

export function ChartCard({ title, children, action }: ChartCardProps) {
  const { t } = useTranslation();
  
  return (
    <div className="bg-white rounded-lg shadow-sm p-6 border border-gray-100">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-lg font-heading font-semibold text-gray-800">{t(title)}</h3>
        {action}
      </div>
      {children}
    </div>
  );
}

// Pie Chart
interface PieChartData {
  name: string;
  value: number;
  color: string;
}

interface PieChartComponentProps {
  data: PieChartData[];
  innerRadius?: number;
  outerRadius?: number;
  cx?: string | number;
  cy?: string | number;
}

export function PieChartComponent({
  data,
  innerRadius = 60,
  outerRadius = 80,
  cx = "50%",
  cy = "50%"
}: PieChartComponentProps) {
  return (
    <div className="h-64">
      <ResponsiveContainer width="100%" height="100%">
        <PieChart>
          <Pie
            data={data}
            cx={cx}
            cy={cy}
            innerRadius={innerRadius}
            outerRadius={outerRadius}
            paddingAngle={5}
            dataKey="value"
            label={({ name, percent }) => `${name}: ${(percent * 100).toFixed(0)}%`}
          >
            {data.map((entry, index) => (
              <Cell key={`cell-${index}`} fill={entry.color} />
            ))}
          </Pie>
          <Tooltip 
            formatter={(value, name) => [value, name]}
            labelFormatter={() => ''}
          />
        </PieChart>
      </ResponsiveContainer>
    </div>
  );
}

// Bar Chart
interface BarChartData {
  name: string;
  value: number;
  color?: string;
}

interface BarChartComponentProps {
  data: BarChartData[];
  xAxisDataKey?: string;
  barDataKey?: string;
  barSize?: number;
  layout?: 'horizontal' | 'vertical';
  colors?: string[];
}

export function BarChartComponent({
  data,
  xAxisDataKey = "name",
  barDataKey = "value",
  barSize = 20,
  layout = 'horizontal',
  colors = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444"]
}: BarChartComponentProps) {
  return (
    <div className="h-64">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          layout={layout}
          data={data}
          margin={{ top: 5, right: 30, left: 20, bottom: 5 }}
        >
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey={xAxisDataKey} />
          <YAxis />
          <Tooltip />
          <Bar dataKey={barDataKey} barSize={barSize}>
            {data.map((entry, index) => (
              <Cell 
                key={`cell-${index}`} 
                fill={entry.color || colors[index % colors.length]} 
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}

// Line Chart
interface LineChartData {
  name: string;
  value: number;
}

interface LineChartComponentProps {
  data: LineChartData[];
  xAxisDataKey?: string;
  lineDataKey?: string;
  color?: string;
}

export function LineChartComponent({
  data,
  xAxisDataKey = "name",
  lineDataKey = "value",
  color = "#3B82F6"
}: LineChartComponentProps) {
  return (
    <div className="h-64">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart
          data={data}
          margin={{ top: 5, right: 30, left: 20, bottom: 5 }}
        >
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey={xAxisDataKey} />
          <YAxis />
          <Tooltip />
          <Line type="monotone" dataKey={lineDataKey} stroke={color} activeDot={{ r: 8 }} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
