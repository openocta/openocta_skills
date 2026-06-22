# -*- coding: utf-8 -*-
import os
import time
import glob
import argparse
import subprocess
import signal


class WeChatDataAnalyzer:
    def __init__(self, excel_path=None, output_dir='/tmp'):
        self.excel_path = excel_path
        self.output_dir = output_dir
        self.df = None
        self.chart_path = None
        os.makedirs(self.output_dir, exist_ok=True)
    
    def load_excel(self, excel_path=None):
        import pandas as pd
        path = excel_path or self.excel_path
        if not path:
            path = self._find_latest_excel()
        
        if not path or not os.path.exists(path):
            print(f"Excel 文件不存在: {path}")
            return False
        
        self.df = pd.read_excel(path, engine='openpyxl')
        
        stat_rows = self.df[self.df['标题'].isin(['最大值', '平均值'])].index
        if len(stat_rows) > 0:
            self.df = self.df.drop(stat_rows).reset_index(drop=True)
        
        numeric_cols = ['阅读数', '点赞数', '分享数', '推荐数', '留言数']
        for col in numeric_cols:
            if col in self.df.columns:
                self.df[col] = pd.to_numeric(self.df[col].astype(str).str.replace(',', ''), errors='coerce').fillna(0).astype(int)
        
        print(f"已加载 Excel: {path}")
        print(f"共 {len(self.df)} 篇文章")
        return True
    
    def _find_latest_excel(self):
        report_dir = '/tmp/wxgzh_reports'
        if not os.path.exists(report_dir):
            return None
        files = glob.glob(os.path.join(report_dir, 'wechat_stats_*.xlsx'))
        if not files:
            return None
        files.sort(key=os.path.getmtime, reverse=True)
        return files[0]
    
    def _shorten_title(self, title, max_len=10):
        if not title or not isinstance(title, str):
            return str(title)
        if len(title) <= max_len:
            return title
        return title[:max_len] + '…'
    
    def _generate_html(self, html_path):
        titles = [self._shorten_title(t) for t in self.df['标题'].tolist()]
        
        bar_option = {
            'title': {'text': '文章阅读数分析', 'subtext': f'共 {len(self.df)} 篇文章', 'left': 'center'},
            'tooltip': {'trigger': 'axis'},
            'xAxis': {'type': 'category', 'data': titles, 'axisLabel': {'rotate': 30, 'fontSize': 10}},
            'yAxis': {'type': 'value', 'name': '阅读数'},
            'series': [{'name': '阅读数', 'type': 'bar', 'data': self.df['阅读数'].tolist(), 
                       'itemStyle': {'color': '#5470C6'}, 'label': {'show': True, 'position': 'top', 'fontSize': 9}}]
        }
        
        line_option = {
            'title': {'text': '互动数据趋势（堆叠）', 'left': 'center'},
            'tooltip': {'trigger': 'axis'},
            'legend': {'data': ['点赞数', '分享数', '推荐数', '留言数'], 'top': '8%'},
            'xAxis': {'type': 'category', 'boundaryGap': False, 'data': titles, 'axisLabel': {'rotate': 30, 'fontSize': 10}},
            'yAxis': {'type': 'value', 'name': '数量'},
            'series': [
                {'name': '点赞数', 'type': 'line', 'stack': 'Total', 'areaStyle': {}, 'data': self.df['点赞数'].tolist()},
                {'name': '分享数', 'type': 'line', 'stack': 'Total', 'areaStyle': {}, 'data': self.df['分享数'].tolist()},
                {'name': '推荐数', 'type': 'line', 'stack': 'Total', 'areaStyle': {}, 'data': self.df['推荐数'].tolist()},
                {'name': '留言数', 'type': 'line', 'stack': 'Total', 'areaStyle': {}, 'data': self.df['留言数'].tolist()},
            ]
        }
        
        pie_data = []
        for col in ['阅读数', '点赞数', '分享数', '推荐数', '留言数']:
            if col in self.df.columns:
                pie_data.append({'name': f'{col}({int(self.df[col].max())})', 'value': int(self.df[col].max())})
        
        pie_option = {
            'title': {'text': '各指标最大值分布', 'left': 'center'},
            'tooltip': {'trigger': 'item', 'formatter': '{b}: {c} ({d}%)'},
            'legend': {'orient': 'horizontal', 'top': '8%'},
            'series': [{'name': '最大值', 'type': 'pie', 'radius': ['30%', '60%'], 'center': ['50%', '60%'],
                       'data': pie_data, 'label': {'formatter': '{b}\n{d}%'}}],
            'color': ['#5470C6', '#EE6666', '#FAC858', '#73C0DE', '#91CC75']
        }
        
        import json
        html = f'''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <script src="https://xiaoyaozi666.oss-cn-beijing.aliyuncs.com/kali/echarts.min.js"></script>
    <style>
        body {{ margin: 0; padding: 20px; background: #fff; }}
        h1 {{ text-align: center; color: #333; }}
        .chart {{ width: 1200px; height: 500px; margin: 10px auto; }}
    </style>
</head>
<body>
    <h1>微信公众号数据分析报告</h1>
    <div id="bar" class="chart"></div>
    <div id="line" class="chart"></div>
    <div id="pie" class="chart"></div>
    <script>
        echarts.init(document.getElementById('bar')).setOption({json.dumps(bar_option, ensure_ascii=False)});
        echarts.init(document.getElementById('line')).setOption({json.dumps(line_option, ensure_ascii=False)});
        echarts.init(document.getElementById('pie')).setOption({json.dumps(pie_option, ensure_ascii=False)});
    </script>
</body>
</html>'''
        
        with open(html_path, 'w', encoding='utf-8') as f:
            f.write(html)
    
    def _screenshot(self, html_path, output_path):
        from playwright.sync_api import sync_playwright
        
        html_path = os.path.abspath(html_path)
        
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page(viewport={'width': 1300, 'height': 1800})
            page.goto(f'file://{html_path}', wait_until='networkidle', timeout=60000)
            print("等待页面加载...")
            time.sleep(20)
            page.screenshot(path=output_path, full_page=True)
            browser.close()
        
        return os.path.exists(output_path) and os.path.getsize(output_path) > 10000
    
    def analyze(self, excel_path=None):
        if not self.load_excel(excel_path):
            return None
        
        if self.df.empty:
            print("没有数据")
            return None
        
        print("\n生成图表...")
        
        html_path = os.path.join(self.output_dir, 'wxgzh_analysis.html')
        self._generate_html(html_path)
        print(f"HTML: {html_path}")
        
        self.chart_path = os.path.join(self.output_dir, 'wxgzh_analysis.png')
        
        print("渲染中...")
        if self._screenshot(html_path, self.chart_path):
            print(f"\n✓ 完成: {self.chart_path}")
            return self.chart_path
        print("截图失败")
        return None


def main():
    parser = argparse.ArgumentParser(description='微信公众号数据分析')
    parser.add_argument('-f', '--file', type=str, default=None)
    parser.add_argument('-o', '--output', type=str, default='/tmp')
    args = parser.parse_args()
    
    analyzer = WeChatDataAnalyzer(output_dir=args.output)
    chart_path = analyzer.analyze(excel_path=args.file)
    
    if chart_path:
        print(f"\nMEDIA:{chart_path}")


if __name__ == '__main__':
    main()
