# 行政处罚记录(lj_iceberg.pboccr2d.dsst_eds_gaa02_pap_record)
page_id: 39c617cf-3593-8051-aadc-d226fdd53918


| 字段解释 | 字段名称 | 备注 | 数值类型 | 字段编码 |
| 自增主键ID | 主键ID |  | long | id |
| 报告ID | 报告ID |  | varchar(32) | id_unqf |
| 客户ID | 客户ID |  | varchar(32) | id_unqp |
|  | 处罚机构 |  | varchar(32) | punish_org |
|  | 处罚内容 |  | varchar(256) | punish_content |
|  | 处罚金额 |  | int | punish_amount |
|  | 生效日期 |  | date | start_date |
|  | 截止日期 |  | date | end_date |
|  | 行政复议结果 |  | varchar(32) | ar_result |
|  | 系统插入时间 |  | datetime | time_inst |