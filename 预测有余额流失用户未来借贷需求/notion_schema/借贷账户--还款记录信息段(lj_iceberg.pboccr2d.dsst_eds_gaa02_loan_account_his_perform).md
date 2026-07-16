# 借贷账户--还款记录信息段(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform)
page_id: 39c617cf-3593-8020-ac75-f9ec7a7a950c


| 字段编码 | 数值类型 | 字段解释 | 字段名称 | 备注 |
| id | long | 自增主键ID | 主键ID |  |
| id_unqf | varchar(32) | 报告ID | 报告ID |  |
| id_unqp | varchar(32) | 客户ID | 客户ID |  |
| account_no | varchar(60) | 账户标识 | 账户标识 |  |
| m24_startm | varchar(32) | 起始年月 | 起始年月最近24m |  |
| m24_endm | varchar(32) | 截止年月 | 截止年月最近24m |  |
| repay_state_24m | varchar(128) | 还款状态最近24m | 还款状态信息(24m) | 数据格式:月份:还款状态，月份:还款状态还款状态对应字典:ploan_repay_r1_state_code等还款状态表 |
| y5_startm | varchar(32) |  | 起始年月最近5Y |  |
| y5_endm | varchar(32) |  | 截止年月最近5Y |  |
| repay_state_5y | varchar(2056) | 还款状态5y | 还款状态信息(5y) | 数据格式:月份:还款状态:逾期/透支总额还款状态对应字典:ploan_repay_r1_state_code等还款状态表 |
| time_inst | datatime | 插入时间 | 插入时间 |  |