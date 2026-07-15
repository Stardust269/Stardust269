# 个人风险评分(lj_iceberg.dsst.pboc2_gaa02_person_risk_score)
page_id: 39c617cf-3593-8038-ad0e-e4318fd0d2cf


| 字段名称 | 备注 | 数值类型 | 字段编码 | 字段解释 |
| 唯一标识 |  | long | Id | 自增主键 |
| 报告ID |  | varchar(32) | id_unqf | 报告ID |
| 客户ID |  | varchar(32) | id_unqp | 客户ID |
| 个人得分(score) |  | int | score | 个人得分 |
| 得分相对位置 |  | int | position_num | 得分相对位置 |
| 分数说明1 | 对应字典：score_affect_type_code | varchar(8) | score_affect | 分数说明1 |
| 分数说明2 | 对应字典：score_affect_type_code | varchar(8) | score_affect2 | 分数说明2 |
| 插入时间 |  | datatime | time_inst | 插入时间 |