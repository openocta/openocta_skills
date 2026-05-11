# 微信公众号数据分析器

自动登录微信公众平台，分析文章数据并生成Excel报告的Python工具。

## 功能特性

- ✅ 自动登录微信公众平台（支持扫码登录）
- ✅ 分析近一周或近一个月的文章数据
- ✅ 统计阅读量、点赞数、评论数等指标
- ✅ 生成Excel格式的详细报告
- ✅ 支持无头浏览器模式

## 安装依赖

```bash
cd scripts
pip install -r requirements.txt
```

## 使用方法

### 方法一：直接运行

```bash
cd scripts
python wechat_gzh_analyzer.py
```

### 方法二：使用启动脚本

**Windows:**
```bash
cd scripts
run.bat
```

**Linux/Mac:**
```bash
cd scripts
chmod +x run.sh
./run.sh
```

### 方法三：作为模块使用

```python
from wechat_gzh_analyzer import WeChatGZHAnalyzer

# 创建分析器实例
analyzer = WeChatGZHAnalyzer(headless=True)

# 分析近一周数据
analyzer.analyze(days=7)

# 或分析近一个月数据
analyzer.analyze(days=30)
```

## 工作流程

1. **启动浏览器** - 配置并启动Chrome无头浏览器
2. **扫码登录** - 访问微信公众平台，截图二维码供用户扫描
3. **数据抓取** - 登录成功后，抓取文章列表和统计数据
4. **生成报告** - 将数据整理并导出为Excel文件
5. **发送文件** - 将报告发送到微信会话（需要集成微信API）

## 输出文件

生成的Excel文件包含两个工作表：

1. **详细数据** - 每篇文章的详细统计信息
2. **汇总统计** - 整体数据的汇总分析

## 注意事项

1. **浏览器驱动** - 需要安装ChromeDriver，确保版本与Chrome浏览器匹配
2. **登录超时** - 扫码登录有效期为5分钟，超时需重新运行
3. **页面变化** - 微信后台页面结构可能变化，需要更新选择器
4. **性能优化** - 无头模式性能更好，调试时可关闭无头模式

## 故障排查

### 问题：浏览器启动失败

**解决方案：**
- 检查Chrome浏览器是否已安装
- 确认ChromeDriver版本与Chrome版本匹配
- 尝试更新selenium库：`pip install --upgrade selenium`

### 问题：登录超时

**解决方案：**
- 确保在5分钟内完成扫码
- 检查网络连接是否正常
- 尝试重新运行程序

### 问题：数据抓取失败

**解决方案：**
- 微信后台页面可能已更新，需要调整代码中的选择器
- 检查是否有足够的权限访问数据
- 查看控制台输出的错误信息

## 技术栈

- **Python 3.7+**
- **Selenium** - 浏览器自动化
- **Pandas** - 数据处理
- **OpenPyXL** - Excel文件生成

## 许可证

MIT License

## 联系方式

微信公众号 kali笔记
