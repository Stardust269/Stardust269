# 查询记录概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary)
page_id: 39c617cf-3593-80ca-a4bd-e241bf6e9f50


| 字段名称 | 数值类型 | 备注 | 字段解释 | 字段编码 |
| 主键ID | long |  | 自增主键ID | id |
| 报告ID | varchar(32) |  | 报告ID | id_unqf |
| 客户ID | varchar(32) |  | 客户ID | id_unqp |
| 上一次查询日期 | date |  | 上一次查询日期 | last_query_date |
| 上一次查询机构类型 | varchar(32) | 对应字典：institution_type_code | 上一次查询机构类型 | last_query_org_type |
| 上一次查询机构代码 | varchar(32) |  | 上一次查询机构代码 | last_query_org_code |
| 上一次查询原因 | varchar(32) | 对应字典表：query_reason_code | 上一次查询原因 | last_query_reason |
| 最近一月内查询机构数(贷款审批) | short(8) |  | 最近一月内查询机构数(贷款审批) | loan_audit_query_org_num_1m |
| 最近一月内查询机构数(信用卡审批) | short(8) |  | 最近一月内查询机构数(信用卡审批) | credit_audit_query_org_num_1m |
| 最近一月内查询次数(贷款审批) | short(8) |  | 最近一月内查询次数(贷款审批) | loan_audit_query_num_1m |
| 最近一月内查询次数(信用卡审批) | short(8) |  | 最近一月内查询次数(信用卡审批) | credit_audit_query_num_1m |
| 最近一月内查询次数(本人查询) | short(8) |  | 最近一月内查询次数(本人查询) | person_query_num_1m |
| 最近两年内的查询次数(贷后管理) | short(8) |  | 最近两年内的查询次数(贷后管理) | plm_query_num_2y |
| 最近两年内的查询次数(担保资格审查) | short(8) |  | 最近两年内的查询次数(担保资格审查) | assure_query_num_2y |
| 最近两年内的查询次数(特约商户实名审查) | short(8) |  | 最近两年内的查询次数(特约商户实名审查) | sam_query_num_2y |
| 插入时间 | datetime |  | 插入时间 | time_inst |
可直接用于模型训练的特征共5项：
近1个月贷款审批机构数（loan_audit_query_org_num_1m）→ 核心多头借贷指标；
近1个月信用卡审批机构数（credit_audit_query_org_num_1m）→ 信用饥渴信号；
上一次硬查询距今天数（动态计算）→ 需求紧迫性指标；
近1个月硬查询总量（loan_audit_query_num_1m + credit_audit_query_num_1m）→ 综合频率指标；
担保资格审查次数（assure_query_num_2y）→ 高风险行为标识。