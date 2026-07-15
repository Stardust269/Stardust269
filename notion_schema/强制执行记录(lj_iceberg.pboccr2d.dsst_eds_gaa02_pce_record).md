# 强制执行记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pce_record)
page_id: 39c617cf-3593-80fa-9d0a-dc49a0ff7911


| 字段名称 | 征信报告数据获取来源 | 字段解释 | 数值类型 | 字段编码 |
| 主键ID |  | 自增主键ID | long | id |
| 报告ID |  | 报告ID | varchar(32) | id_unqf |
| 客户ID |  | 客户ID | varchar(32) | id_unqp |
| 执行法院 |  |  | varchar(100) | court_exc |
| 执行案由 |  |  | varchar(50) | rsn_excact |
| 立案日期 |  |  | date | date_filcase |
| 结案方式 | 对应状态表：juge_close_type_code |  | varchar(50) | type_cloway |
| 案件状态 |  |  | varchar(50) | stu_case |
| 结案日期 |  |  | date | date_clocase |
| 申请执行标的 |  |  | varchar(100) | sub_appexc |
| 申请执行标的价值 |  |  | int | pri_appexcsub |
| 已执行标的 |  |  | varchar(100) | sub_perf |
| 已执行标的金额 |  |  | decimal | pri_perfsub |
| 系统插入记录时间 |  |  | datetime | time_inst |
可直接用于模型训练的特征共3项：
已执行比例 → 区分"失信"与"失能"的核心依据；
结案方式与案件状态的关联标签 → 识别恶意规避执行的关键信号；
立案到结案时长 → 量化被执行人配合度的动态指标。