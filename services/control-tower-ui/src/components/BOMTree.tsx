import { useQuery } from "@apollo/client";
import { GET_BOM } from "../graphql/queries";

interface PartNode {
  id: string;
  name: string;
  partType: string;
  suppliedBy?: Array<{ id: string; name: string }>;
  components?: PartNode[];
}

const PART_TYPE_LABELS: Record<string, string> = {
  Assembly: "组件",
  Component: "零件",
};

function BOMNode({ part, depth }: { part: PartNode; depth: number }) {
  return (
    <div className="bom-node" style={{ marginLeft: depth * 24 }}>
      <div className="bom-item">
        <span className={`part-type ${part.partType.toLowerCase()}`}>
          {PART_TYPE_LABELS[part.partType] ?? part.partType}
        </span>
        <strong>{part.name}</strong>
        <span className="part-id">({part.id})</span>
        {part.suppliedBy && part.suppliedBy.length > 0 && (
          <span className="supplier-tags">
            {part.suppliedBy.map((s) => (
              <span key={s.id} className="tag tag-supplier">{s.name}</span>
            ))}
          </span>
        )}
      </div>
      {part.components?.map((child) => (
        <BOMNode key={child.id} part={child} depth={depth + 1} />
      ))}
    </div>
  );
}

export default function BOMTree() {
  const { data, loading, error } = useQuery(GET_BOM);

  if (loading) return <p className="loading">加载物料清单中...</p>;
  if (error) return <p className="error">错误: {error.message}</p>;

  const products = data?.products ?? [];

  return (
    <div className="bom-tree">
      {products.map((product: { id: string; name: string; components: PartNode[] }) => (
        <div key={product.id} className="bom-product">
          <h3>
            {product.name} <span className="part-id">({product.id})</span>
          </h3>
          {product.components?.map((part) => (
            <BOMNode key={part.id} part={part} depth={0} />
          ))}
        </div>
      ))}
    </div>
  );
}
