# -*- coding: utf-8 -*-
import subprocess
import json
import time
import os
import re
import argparse
import signal
from datetime import datetime, timedelta
import pandas as pd


def kill_chrome_processes():
    print("清理可能存在的 Chrome 进程...")
    try:
        subprocess.run("pkill -9 -f 'chrome.*openclaw' 2>/dev/null || true", shell=True)
        subprocess.run("pkill -9 -f 'chromium.*openclaw' 2>/dev/null || true", shell=True)
        time.sleep(1)
    except Exception as e:
        print(f"清理进程时出错: {e}")


def cleanup_browser_locks():
    browser_data_dir = os.path.expanduser("~/.openclaw/browser/openclaw/user-data")
    lock_files = ["SingletonLock", "SingletonSocket", "SingletonCookie"]
    
    print(f"清理浏览器锁文件: {browser_data_dir}")
    
    for lock_name in lock_files:
        lock_path = os.path.join(browser_data_dir, lock_name)
        if os.path.exists(lock_path):
            try:
                os.remove(lock_path)
                print(f"  已删除: {lock_path}")
            except Exception as e:
                print(f"  删除失败 {lock_path}: {e}")
        else:
            print(f"  不存在: {lock_path}")


class PlaywrightBrowser:
    def __init__(self):
        self.playwright = None
        self.browser = None
        self.context = None
        self.page = None
        self.cdp_port = 18800
        self.chrome_process = None
        
    def start(self):
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            print("错误: 未安装 Playwright，请运行: pip install playwright && playwright install chromium")
            return False
        
        kill_chrome_processes()
        cleanup_browser_locks()
        
        print("启动 Playwright 浏览器...")
        
        try:
            self.playwright = sync_playwright().start()
            
            self.browser = self.playwright.chromium.launch(
                headless=True,
                args=[
                    '--disable-blink-features=AutomationControlled',
                    '--no-sandbox',
                    '--disable-setuid-sandbox',
                    '--disable-dev-shm-usage',
                    '--disable-gpu',
                    '--hide-scrollbars',
                    '--mute-audio',
                ]
            )
            
            self.context = self.browser.new_context(
                viewport={'width': 1280, 'height': 800},
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            )
            
            self.page = self.context.new_page()
            
            self.page.add_init_script("""
                Object.defineProperty(navigator, 'webdriver', {
                    get: () => undefined
                })
            """)
            
            print("浏览器启动成功！")
            return True
            
        except Exception as e:
            print(f"浏览器启动失败: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    def open(self, url):
        if self.page:
            self.page.goto(url, wait_until='networkidle', timeout=60000)
            
    def screenshot(self, output_path, full_page=False):
        if not self.page:
            return None
            
        dir_path = os.path.dirname(output_path)
        if dir_path and not os.path.exists(dir_path):
            os.makedirs(dir_path, exist_ok=True)
        
        try:
            self.page.screenshot(path=output_path, full_page=full_page)
            print(f"截图已保存: {output_path}")
            return output_path
        except Exception as e:
            print(f"截图失败: {e}")
            return None
    
    def get_url(self):
        if self.page:
            try:
                return self.page.url
            except:
                return ""
        return ""
    
    def get_page_source(self):
        if self.page:
            try:
                return self.page.content()
            except Exception as e:
                return ""
        return ""
    
    def wait_for_load(self, timeout=5000):
        if self.page:
            try:
                self.page.wait_for_load_state('domcontentloaded', timeout=timeout)
            except:
                pass
    
    def close(self):
        try:
            if self.page:
                self.page.close()
            if self.context:
                self.context.close()
            if self.browser:
                self.browser.close()
            if self.playwright:
                self.playwright.stop()
        except:
            pass
        
        kill_chrome_processes()
        cleanup_browser_locks()
        print("浏览器已关闭")


class WeChatArticleSpider:
    def __init__(self, time_filter=None):
        self.browser = PlaywrightBrowser()
        self.articles = []
        self.token = None
        self.time_filter = time_filter
        self.output_dir = "/tmp/wxgzh_reports"
        self.screenshot_dir = "/tmp/wxgzh_screenshots"
        
        os.makedirs(self.output_dir, exist_ok=True)
        os.makedirs(self.screenshot_dir, exist_ok=True)
        
    def extract_token(self, url):
        if 'token=' in url:
            token_start = url.find('token=') + 6
            token_end = url.find('&', token_start)
            if token_end == -1:
                return url[token_start:]
            else:
                return url[token_start:token_end]
        return None
    
    def send_to_clawbot(self, message, media_path=None):
        print(f"\n{'='*50}")
        print(message)
        if media_path and os.path.exists(media_path):
            print(f"MEDIA:{media_path}")
        print(f"{'='*50}\n")
        
    def check_login_success(self):
        try:
            current_url = self.browser.get_url()
            
            if 'cgi-bin' in current_url:
                print(f"检测到 URL 包含 cgi-bin: {current_url}")
                return True
            
            if 'token=' in current_url:
                print(f"检测到 URL 包含 token: {current_url}")
                return True
            
            if current_url != 'https://mp.weixin.qq.com/' and 'mp.weixin.qq.com' in current_url:
                print(f"检测到 URL 已跳转: {current_url}")
                return True
            
            self.browser.wait_for_load(timeout=3000)
            
            page_source = self.browser.get_page_source()
            
            if not page_source:
                return False
            
            if '首页' in page_source and '图文消息' in page_source:
                print("检测到页面包含公众号后台元素")
                return True
            
            if '新建图文' in page_source or '已发送' in page_source:
                print("检测到页面包含已发送/新建图文元素")
                return True
            
            if 'weui-desktop-account' in page_source:
                print("检测到公众号后台桌面版元素")
                return True
            
            return False
            
        except Exception as e:
            print(f"检查登录状态出错: {e}")
            return False
    
    def login(self):
        print("正在打开微信公众平台登录页面...")
        self.browser.open('https://mp.weixin.qq.com/')
        
        time.sleep(3)
        
        screenshot_path = os.path.join(self.screenshot_dir, "login_qrcode.png")
        result = self.browser.screenshot(screenshot_path)
        
        if result and os.path.exists(result):
            self.send_to_clawbot(
                "请使用微信扫描上方二维码登录微信公众平台",
                screenshot_path
            )
        else:
            print("警告: 截图失败")
        
        print("等待用户扫码登录...")
        print("提示: 扫码后请在手机上确认登录")
        
        max_wait_time = 300
        start_time = time.time()
        last_url = ""
        check_count = 0
        
        while time.time() - start_time < max_wait_time:
            check_count += 1
            current_url = self.browser.get_url()
            
            if current_url != last_url:
                print(f"[{check_count}] URL 变化: {current_url}")
                last_url = current_url
            
            if self.check_login_success():
                time.sleep(2)
                self.browser.wait_for_load(timeout=5000)
                current_url = self.browser.get_url()
                self.token = self.extract_token(current_url)
                
                if not self.token:
                    try:
                        page_source = self.browser.get_page_source()
                        token_match = re.search(r'token[=:]\s*["\']?(\d+)', page_source)
                        if token_match:
                            self.token = token_match.group(1)
                    except:
                        pass
                
                print(f"登录成功！Token: {self.token}")
                
                login_success_path = os.path.join(self.screenshot_dir, "login_success.png")
                self.browser.screenshot(login_success_path)
                print(f"登录成功截图: {login_success_path}")
                
                return True
            
            if check_count % 10 == 0:
                elapsed = int(time.time() - start_time)
                print(f"已等待 {elapsed} 秒，当前 URL: {current_url[:80]}...")
            
            time.sleep(2)
        
        print("登录超时，请重试")
        return False
    
    def navigate_to_page(self, page_num):
        begin = (page_num - 1) * 10
        if self.token:
            url = f'https://mp.weixin.qq.com/cgi-bin/appmsgpublish?sub=list&begin={begin}&count=10&token={self.token}&lang=zh_CN'
        else:
            url = f'https://mp.weixin.qq.com/cgi-bin/appmsgpublish?sub=list&begin={begin}&count=10'
        
        print(f"导航到: {url}")
        self.browser.open(url)
        self.browser.wait_for_load(timeout=10000)
        time.sleep(3)
        
    def parse_publish_time(self, time_str):
        try:
            now = datetime.now()
            time_str = time_str.strip()
            
            if '今天' in time_str:
                time_part = time_str.replace('今天', '').strip()
                hour, minute = map(int, time_part.split(':'))
                return now.replace(hour=hour, minute=minute, second=0, microsecond=0)
            
            elif '昨天' in time_str:
                time_part = time_str.replace('昨天', '').strip()
                hour, minute = map(int, time_part.split(':'))
                yesterday = now - timedelta(days=1)
                return yesterday.replace(hour=hour, minute=minute, second=0, microsecond=0)
            
            elif '前天' in time_str:
                time_part = time_str.replace('前天', '').strip()
                hour, minute = map(int, time_part.split(':'))
                day_before = now - timedelta(days=2)
                return day_before.replace(hour=hour, minute=minute, second=0, microsecond=0)
            
            elif re.match(r'\d+月\d+日', time_str):
                match = re.match(r'(\d+)月(\d+)日\s*(\d+):(\d+)?', time_str)
                if match:
                    month = int(match.group(1))
                    day = int(match.group(2))
                    hour = int(match.group(3))
                    minute = int(match.group(4)) if match.group(4) else 0
                    year = now.year
                    if month > now.month:
                        year -= 1
                    return datetime(year, month, day, hour, minute)
            
            elif re.match(r'\d{4}年\d+月\d+日', time_str):
                match = re.match(r'(\d{4})年(\d+)月(\d+)日\s*(\d+):(\d+)?', time_str)
                if match:
                    year = int(match.group(1))
                    month = int(match.group(2))
                    day = int(match.group(3))
                    hour = int(match.group(4))
                    minute = int(match.group(5)) if match.group(5) else 0
                    return datetime(year, month, day, hour, minute)
            
            return None
            
        except Exception as e:
            return None
    
    def is_in_time_range(self, publish_time):
        if not self.time_filter or not publish_time:
            return True
        
        now = datetime.now()
        if self.time_filter == 'week':
            start_time = now - timedelta(days=7)
        elif self.time_filter == 'month':
            start_time = now - timedelta(days=30)
        else:
            return True
        
        return publish_time >= start_time
    
    def parse_page_content(self):
        page_source = self.browser.get_page_source()
        
        debug_path = os.path.join(self.screenshot_dir, "page_source_debug.html")
        with open(debug_path, 'w', encoding='utf-8') as f:
            f.write(page_source)
        print(f"页面源码已保存到: {debug_path}")
        
        articles = []
        
        article_blocks = re.split(r'<div class="weui-desktop-block"><!---->', page_source)
        print(f"分割到 {len(article_blocks) - 1} 个文章块")
        
        for match in article_blocks[1:]:
            article_data = {}
            
            time_match = re.search(r'<em class="weui-desktop-mass__time">([^<]+)</em>', match)
            article_data['发布时间'] = time_match.group(1).strip() if time_match else ''
            
            title_match = re.search(r'<a[^>]*href="([^"]*)"[^>]*class="weui-desktop-mass-appmsg__title"[^>]*>\s*<span>([^<]+)</span>', match)
            if title_match:
                article_data['链接'] = title_match.group(1).replace('&amp;', '&')
                article_data['标题'] = title_match.group(2).strip()
            else:
                print(f"  标题匹配失败，跳过")
                continue
            
            data_items = re.findall(r'<span class="weui-desktop-mass-media__data__inner">([^<]+)</span>', match)
            
            comment_match = re.search(r'<span class="js_comment_info weui-desktop-mass-media__data__inner">\s*<span class="weui-desktop-link">([^<]+)</span>', match)
            
            if len(data_items) >= 1:
                article_data['阅读数'] = data_items[0].strip()
            else:
                article_data['阅读数'] = ''
            
            if len(data_items) >= 2:
                article_data['点赞数'] = data_items[1].strip()
            else:
                article_data['点赞数'] = ''
            
            if len(data_items) >= 3:
                article_data['分享数'] = data_items[2].strip()
            else:
                article_data['分享数'] = ''
            
            if len(data_items) >= 4:
                article_data['推荐数'] = data_items[3].strip()
            else:
                article_data['推荐数'] = ''
            
            if comment_match:
                article_data['留言数'] = comment_match.group(1).strip()
            elif len(data_items) >= 5:
                article_data['留言数'] = data_items[4].strip()
            else:
                article_data['留言数'] = ''
            
            article_data['爬取时间'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            
            articles.append(article_data)
            print(f"  解析成功: {article_data['标题']}")
        
        return articles
    
    def scrape_articles(self, max_pages=10):
        print(f"\n开始爬取文章列表（最多 {max_pages} 页）...")
        if self.time_filter:
            filter_name = '一周内' if self.time_filter == 'week' else '一月内'
            print(f"时间筛选: {filter_name}")
        
        page_count = 0
        should_stop = False
        
        while page_count < max_pages:
            page_count += 1
            print(f"\n正在爬取第 {page_count} 页...")
            
            self.navigate_to_page(page_count)
            
            time.sleep(3)
            
            page_articles = self.parse_page_content()
            
            if not page_articles:
                print("未找到文章元素，可能已到末尾")
                break
            
            print(f"找到 {len(page_articles)} 篇文章")
            
            page_articles_count = 0
            for article_info in page_articles:
                if article_info.get('标题'):
                    publish_time = self.parse_publish_time(article_info.get('发布时间', ''))
                    
                    if self.time_filter and publish_time:
                        if not self.is_in_time_range(publish_time):
                            print(f"  跳过（超出时间范围）: {article_info['标题']}")
                            should_stop = True
                            continue
                    
                    self.articles.append(article_info)
                    page_articles_count += 1
                    print(f"  [{len(self.articles)}] {article_info['标题']} ({article_info.get('发布时间', '')})")
            
            if should_stop and page_articles_count == 0:
                print("\n已超出时间筛选范围，停止爬取")
                break
        
        print(f"\n爬取完成！共获取 {len(self.articles)} 篇文章")
        return self.articles
    
    def save_to_excel(self, filename=None):
        if not self.articles:
            print("没有文章数据可保存")
            return None
        
        if filename is None:
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            if self.time_filter:
                filter_suffix = '_week' if self.time_filter == 'week' else '_month'
                filename = f'wechat_stats_{timestamp}{filter_suffix}.xlsx'
            else:
                filename = f'wechat_stats_{timestamp}.xlsx'
        
        df = pd.DataFrame(self.articles)
        
        columns_order = ['标题', '发布时间', '阅读数', '点赞数', '分享数', '推荐数', '留言数', '链接', '爬取时间']
        existing_columns = [col for col in columns_order if col in df.columns]
        other_columns = [col for col in df.columns if col not in columns_order]
        df = df[existing_columns + other_columns]
        
        numeric_cols = ['阅读数', '点赞数', '分享数', '推荐数', '留言数']
        for col in numeric_cols:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col].astype(str).str.replace(',', ''), errors='coerce').fillna(0).astype(int)
        
        max_row = {'标题': '最大值'}
        avg_row = {'标题': '平均值'}
        for col in df.columns:
            if col in numeric_cols and col in df.columns:
                max_row[col] = df[col].max()
                avg_row[col] = round(df[col].mean(), 1)
            elif col != '标题':
                max_row[col] = ''
                avg_row[col] = ''
        
        df = pd.concat([df, pd.DataFrame([max_row, avg_row])], ignore_index=True)
        
        filepath = os.path.join(self.output_dir, filename)
        df.to_excel(filepath, index=False, engine='openpyxl')
        
        print(f"\n文章已保存到: {filepath}")
        print(f"共保存 {len(df) - 2} 条记录（含最大值/平均值统计行）")
        
        return filepath
    
    def run(self, max_pages=10):
        try:
            print("="*60)
            print("微信公众号文章爬虫 (Playwright 版)")
            print("="*60)
            
            print("\n启动浏览器...")
            if not self.browser.start():
                print("浏览器启动失败！")
                return None
            
            if not self.login():
                return None
            
            self.scrape_articles(max_pages)
            
            filepath = self.save_to_excel()
            
            if filepath:
                self.send_to_clawbot(
                    f"爬虫任务完成！共爬取 {len(self.articles)} 篇文章。\nExcel 报告已生成，请查收。",
                    filepath
                )
            
            return filepath
            
        except Exception as e:
            print(f"\n程序出错: {e}")
            import traceback
            traceback.print_exc()
            return None
            
        finally:
            print("\n关闭浏览器...")
            self.browser.close()


def main():
    parser = argparse.ArgumentParser(description='微信公众号文章爬虫 (Playwright 版)')
    parser.add_argument('-p', '--pages', type=int, default=10, 
                        help='要爬取的最大页数 (默认: 10)')
    parser.add_argument('-t', '--time', type=str, default=None,
                        choices=['week', 'month'], help='时间筛选: week=一周内, month=一月内')
    
    args = parser.parse_args()
    
    max_pages = args.pages
    time_filter = args.time
    
    print(f"\n最大爬取页数: {max_pages}")
    if time_filter:
        filter_name = '一周内' if time_filter == 'week' else '一月内'
        print(f"时间筛选: {filter_name}")
    
    spider = WeChatArticleSpider(time_filter=time_filter)
    spider.run(max_pages=max_pages)


if __name__ == '__main__':
    main()
